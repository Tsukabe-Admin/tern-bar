//! `skua-helper clipboard` against a stand-in compositor.
//!
//! The stand-in is a small Wayland server (the server side of the library the
//! job itself uses) that offers a seat and data control, and plays both the
//! compositor and the apps that copy and paste. The job runs as the real
//! program and reaches it through `WAYLAND_SOCKET`, an already open
//! connection, with `WAYLAND_DISPLAY` removed: no real Wayland session is ever
//! touched.

use std::collections::HashMap;
use std::ffi::CString;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::fd::{AsRawFd, BorrowedFd, OwnedFd};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::UnixStream;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use serde_json::{json, Value};
use wayland_backend::protocol::{Argument, Interface, Message};
use wayland_backend::server::{
    Backend, ClientId, GlobalHandler, GlobalId, Handle, ObjectData, ObjectId,
};
use wayland_backend::smallvec::smallvec;
use wayland_client::protocol::wl_seat::WlSeat;
use wayland_client::Proxy;
use wayland_protocols::ext::data_control::v1::client as ext;
use wayland_protocols_wlr::data_control::v1::client as wlr;

const TEXT_TYPES: [&str; 5] = [
    "text/plain;charset=utf-8",
    "UTF8_STRING",
    "text/plain",
    "TEXT",
    "STRING",
];

/// A real 3×2 PNG.
const PNG: [u8; 74] = [
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x02, 0x08, 0x02, 0x00, 0x00, 0x00, 0x12, 0x16, 0xf1,
    0x4d, 0x00, 0x00, 0x00, 0x11, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
    0x41, 0x0c, 0x30, 0xc6, 0x7f, 0x00, 0x3b, 0xd8, 0x05, 0xfb, 0x39, 0x4d, 0x96, 0xa5, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
];

// ── The stand-in compositor ────────────────────────────────────────────────

/// One version of data control. Both have the same requests and events, in
/// the same order, so only the names differ.
#[derive(Clone, Copy)]
struct Protocol {
    manager: &'static Interface,
    manager_version: u32,
    offer: &'static Interface,
}

fn ext_protocol() -> Protocol {
    Protocol {
        manager: ext::ext_data_control_manager_v1::ExtDataControlManagerV1::interface(),
        manager_version: 1,
        offer: ext::ext_data_control_offer_v1::ExtDataControlOfferV1::interface(),
    }
}

fn wlr_protocol() -> Protocol {
    Protocol {
        manager: wlr::zwlr_data_control_manager_v1::ZwlrDataControlManagerV1::interface(),
        manager_version: 2,
        offer: wlr::zwlr_data_control_offer_v1::ZwlrDataControlOfferV1::interface(),
    }
}

/// An app that copied something: its content per type, and how long it
/// takes before it writes (a slow or stuck app).
#[derive(Clone)]
struct App {
    contents: Vec<(String, Vec<u8>)>,
    delay: Duration,
}

#[derive(Default)]
struct State {
    client: Option<ClientId>,
    device: Option<ObjectId>,
    /// The job's sources and the types each one offers.
    sources: HashMap<ObjectId, Vec<String>>,
    /// The job's source that is the clipboard now, if it is the job's.
    selection: Option<ObjectId>,
    /// The apps behind the offers.
    apps: HashMap<ObjectId, App>,
    /// Every type the job asked an offer for, in order.
    asked: Vec<String>,
}

struct Shared {
    state: Mutex<State>,
    protocol: Option<Protocol>,
}

#[derive(Clone, Copy, PartialEq)]
enum Role {
    Seat,
    Manager,
    Device,
    Source,
    Offer,
}

struct Object {
    role: Role,
    shared: Arc<Shared>,
}

fn string(text: &str) -> Argument<ObjectId, std::os::fd::RawFd> {
    Argument::Str(Some(Box::new(CString::new(text).unwrap())))
}

impl Shared {
    fn protocol(&self) -> Protocol {
        self.protocol.expect("this compositor has data control")
    }

    /// Announces new clipboard content to the job: a new offer, its types,
    /// then "this is the clipboard now". `app` answers its reads.
    fn announce(self: &Arc<Self>, handle: &Handle, types: &[String], app: Option<App>) {
        let (client, device) = {
            let state = self.state.lock().unwrap();
            (state.client.clone(), state.device.clone())
        };
        let (Some(client), Some(device)) = (client, device) else {
            return;
        };
        let offer = Arc::new(Object {
            role: Role::Offer,
            shared: Arc::clone(self),
        });
        let offer = handle
            .create_object::<()>(client, self.protocol().offer, 1, offer)
            .unwrap();
        if let Some(app) = app {
            self.state.lock().unwrap().apps.insert(offer.clone(), app);
        }
        let send = |sender: &ObjectId, opcode, args| {
            handle
                .send_event(Message {
                    sender_id: sender.clone(),
                    opcode,
                    args,
                })
                .unwrap()
        };
        send(&device, 0, smallvec![Argument::NewId(offer.clone())]);
        for name in types {
            send(&offer, 0, smallvec![string(name)]);
        }
        send(&device, 1, smallvec![Argument::Object(offer)]);
    }

    /// The clipboard is taken from the job's source, if it held it.
    fn take_from_job(&self, handle: &Handle) {
        let old = self.state.lock().unwrap().selection.take();
        if let Some(old) = old {
            let cancelled = Message {
                sender_id: old,
                opcode: 1,
                args: smallvec![],
            };
            let _ = handle.send_event(cancelled);
        }
    }
}

impl ObjectData<()> for Object {
    fn request(
        self: Arc<Self>,
        handle: &Handle,
        _: &mut (),
        client: ClientId,
        msg: Message<ObjectId, OwnedFd>,
    ) -> Option<Arc<dyn ObjectData<()>>> {
        let child = |role| -> Option<Arc<dyn ObjectData<()>>> {
            Some(Arc::new(Object {
                role,
                shared: Arc::clone(&self.shared),
            }))
        };
        let mut args = msg.args.into_iter();
        match (self.role, msg.opcode) {
            // create_data_source
            (Role::Manager, 0) => {
                let Some(Argument::NewId(id)) = args.next() else {
                    panic!("create_data_source without an id")
                };
                self.shared
                    .state
                    .lock()
                    .unwrap()
                    .sources
                    .insert(id, Vec::new());
                child(Role::Source)
            }
            // get_data_device
            (Role::Manager, 1) => {
                let Some(Argument::NewId(id)) = args.next() else {
                    panic!("get_data_device without an id")
                };
                let mut state = self.shared.state.lock().unwrap();
                state.client = Some(client);
                state.device = Some(id);
                child(Role::Device)
            }
            // set_selection: like a real compositor, take the clipboard from
            // the source that had it, then tell every clipboard client (the
            // job too) what is on it now.
            (Role::Device, 0) => {
                let Some(Argument::Object(source)) = args.next() else {
                    panic!("set_selection without a source")
                };
                self.shared.take_from_job(handle);
                let types = {
                    let mut state = self.shared.state.lock().unwrap();
                    state.selection = Some(source.clone());
                    state.sources.get(&source).cloned().unwrap_or_default()
                };
                self.shared.announce(handle, &types, None);
                None
            }
            // offer (a type the job's source has)
            (Role::Source, 0) => {
                let Some(Argument::Str(Some(name))) = args.next() else {
                    panic!("offer without a type")
                };
                let mut state = self.shared.state.lock().unwrap();
                let name = name.to_string_lossy().into_owned();
                state.sources.entry(msg.sender_id).or_default().push(name);
                None
            }
            // receive: the app writes its content into the job's pipe
            (Role::Offer, 0) => {
                let (Some(Argument::Str(Some(name))), Some(Argument::Fd(pipe))) =
                    (args.next(), args.next())
                else {
                    panic!("receive without a type and a pipe")
                };
                let name = name.to_string_lossy().into_owned();
                let app = {
                    let mut state = self.shared.state.lock().unwrap();
                    state.asked.push(name.clone());
                    state.apps.get(&msg.sender_id).cloned()
                };
                if let Some(app) = app {
                    std::thread::spawn(move || {
                        std::thread::sleep(app.delay);
                        let mut pipe = std::fs::File::from(pipe);
                        if let Some((_, data)) = app.contents.iter().find(|(n, _)| *n == name) {
                            // The job may have stopped reading: that is fine.
                            let _ = pipe.write_all(data);
                        }
                    });
                }
                None
            }
            _ => None,
        }
    }

    fn destroyed(self: Arc<Self>, _: &Handle, _: &mut (), _: ClientId, _: ObjectId) {}
}

struct Global {
    role: Role,
    shared: Arc<Shared>,
}

impl GlobalHandler<()> for Global {
    fn bind(
        self: Arc<Self>,
        _: &Handle,
        _: &mut (),
        _: ClientId,
        _: GlobalId,
        _: ObjectId,
    ) -> Arc<dyn ObjectData<()>> {
        Arc::new(Object {
            role: self.role,
            shared: Arc::clone(&self.shared),
        })
    }
}

struct Compositor {
    shared: Arc<Shared>,
    handle: Handle,
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl Compositor {
    /// A compositor with a seat and, unless None, this data control.
    fn new(protocol: Option<Protocol>) -> Compositor {
        let mut backend = Backend::<()>::new().unwrap();
        let handle = backend.handle();
        let shared = Arc::new(Shared {
            state: Mutex::default(),
            protocol,
        });
        let global = |role| {
            Arc::new(Global {
                role,
                shared: Arc::clone(&shared),
            })
        };
        handle.create_global::<()>(WlSeat::interface(), 1, global(Role::Seat));
        if let Some(protocol) = protocol {
            handle.create_global::<()>(
                protocol.manager,
                protocol.manager_version,
                global(Role::Manager),
            );
        }
        let stop = Arc::new(AtomicBool::new(false));
        let stopped = Arc::clone(&stop);
        let thread = std::thread::spawn(move || {
            while !stopped.load(Ordering::Relaxed) {
                let _ = backend.dispatch_all_clients(&mut ());
                let _ = backend.flush(None);
                std::thread::sleep(Duration::from_millis(2));
            }
        });
        Compositor {
            shared,
            handle,
            stop,
            thread: Some(thread),
        }
    }

    /// An app copies something: its types and, for some of them, content.
    fn copy(&self, types: &[&str], contents: &[(&str, &[u8])], delay: Duration) {
        // The job says it is ready before its first requests have reached
        // the compositor.
        let asked = Instant::now();
        while self.shared.state.lock().unwrap().device.is_none() {
            assert!(
                asked.elapsed() < Duration::from_secs(5),
                "the job has no clipboard device"
            );
            std::thread::sleep(Duration::from_millis(5));
        }
        self.shared.take_from_job(&self.handle);
        let app = App {
            contents: contents
                .iter()
                .map(|(name, data)| (name.to_string(), data.to_vec()))
                .collect(),
            delay,
        };
        let types: Vec<String> = types.iter().map(|name| name.to_string()).collect();
        self.shared.announce(&self.handle, &types, Some(app));
    }

    fn copy_text(&self, text: &str) {
        let content = [("text/plain;charset=utf-8", text.as_bytes())];
        self.copy(&["text/plain;charset=utf-8"], &content, Duration::ZERO);
    }

    /// The types of the job's source that holds the clipboard now.
    fn job_types(&self) -> Option<Vec<String>> {
        let state = self.shared.state.lock().unwrap();
        let source = state.selection.as_ref()?;
        state.sources.get(source).cloned()
    }

    fn asked(&self) -> Vec<String> {
        self.shared.state.lock().unwrap().asked.clone()
    }

    /// An app pastes from the job: the compositor hands the job a pipe, and
    /// this reads it, `chunk` bytes at a time with `pause` between reads.
    fn paste(&self, name: &str, chunk: usize, pause: Duration) -> mpsc::Receiver<Vec<u8>> {
        // The job reports a copy as soon as it has asked for the clipboard.
        let asked = Instant::now();
        let source = loop {
            if let Some(source) = self.shared.state.lock().unwrap().selection.clone() {
                break source;
            }
            assert!(
                asked.elapsed() < Duration::from_secs(5),
                "the job never took the clipboard"
            );
            std::thread::sleep(Duration::from_millis(5));
        };
        let (reader, writer) = std::io::pipe().unwrap();
        self.handle
            .send_event(Message {
                sender_id: source,
                opcode: 0,
                args: smallvec![string(name), Argument::Fd(writer.as_raw_fd())],
            })
            .unwrap();
        // The event holds its own copy of the write end now.
        drop(writer);
        let (done, received) = mpsc::channel();
        std::thread::spawn(move || {
            let mut reader = reader;
            let mut got = Vec::new();
            let mut buffer = vec![0; chunk];
            loop {
                match reader.read(&mut buffer) {
                    Ok(0) | Err(_) => break,
                    Ok(read) => got.extend_from_slice(&buffer[..read]),
                }
                std::thread::sleep(pause);
            }
            let _ = done.send(got);
        });
        received
    }
}

impl Drop for Compositor {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

// ── The job ────────────────────────────────────────────────────────────────

struct Job {
    child: Child,
    stdin: Option<ChildStdin>,
    lines: mpsc::Receiver<Value>,
}

impl Job {
    fn start(compositor: &mut Compositor, state_home: &Path) -> Job {
        let (ours, theirs) = UnixStream::pair().unwrap();
        compositor.handle.insert_client(ours, Arc::new(())).unwrap();
        let socket = theirs.as_raw_fd();
        let mut command = Command::new(env!("CARGO_BIN_EXE_skua-helper"));
        command
            .arg("clipboard")
            .env_remove("WAYLAND_DISPLAY")
            .env("WAYLAND_SOCKET", socket.to_string())
            .env("XDG_RUNTIME_DIR", state_home)
            .env("XDG_STATE_HOME", state_home)
            // A cliphist of its own, never the user's settings or history.
            .env("XDG_CONFIG_HOME", state_home)
            .env("SKUA_CLIPHIST_DB", state_home.join("cliphist-db"))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped());
        // SAFETY: only an fcntl between fork and exec, which is safe there.
        unsafe {
            command.pre_exec(move || {
                // The connection has to survive exec in the job.
                let socket = BorrowedFd::borrow_raw(socket);
                rustix::io::fcntl_setfd(socket, rustix::io::FdFlags::empty())?;
                Ok(())
            });
        }
        let mut child = command.spawn().unwrap();
        drop(theirs);
        let stdout = child.stdout.take().unwrap();
        let (sender, lines) = mpsc::channel();
        std::thread::spawn(move || {
            for line in BufReader::new(stdout).lines() {
                let Ok(line) = line else { break };
                let value: Value = serde_json::from_str(&line).expect("a JSON line");
                if sender.send(value).is_err() {
                    break;
                }
            }
        });
        let stdin = child.stdin.take();
        Job {
            child,
            stdin,
            lines,
        }
    }

    fn send(&mut self, command: Value) {
        let stdin = self.stdin.as_mut().unwrap();
        writeln!(stdin, "{command}").unwrap();
        stdin.flush().unwrap();
    }

    /// The next line, which must be this event.
    fn expect(&self, event: &str) -> Value {
        let line = self
            .lines
            .recv_timeout(Duration::from_secs(5))
            .unwrap_or_else(|_| panic!("no {event:?} line"));
        assert_eq!(line["event"], event, "expected {event:?}, got {line}");
        line
    }

    /// No line for a while.
    fn quiet(&self) {
        if let Ok(line) = self.lines.recv_timeout(Duration::from_millis(300)) {
            panic!("unexpected line {line}");
        }
    }

    fn items(&mut self) -> Vec<Value> {
        self.send(json!({"list": true}));
        self.expect("items")["items"].as_array().unwrap().clone()
    }

    /// Closes stdin, as the bar does, and returns the exit status.
    fn end(mut self) -> Option<i32> {
        drop(self.stdin.take());
        let started = Instant::now();
        while started.elapsed() < Duration::from_secs(5) {
            if let Some(status) = self.child.try_wait().unwrap() {
                return status.code();
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        let _ = self.child.kill();
        panic!("the job did not end when stdin closed");
    }
}

impl Drop for Job {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn started(compositor: &mut Compositor, state_home: &Path) -> Job {
    let job = Job::start(compositor, state_home);
    job.expect("hello");
    job
}

fn ids(items: &[Value]) -> Vec<u64> {
    items
        .iter()
        .map(|item| item["id"].as_u64().unwrap())
        .collect()
}

fn mode(path: &Path) -> u32 {
    std::fs::metadata(path).unwrap().permissions().mode() & 0o777
}

// ── Tests ──────────────────────────────────────────────────────────────────

#[test]
fn keeps_text_and_images_and_puts_them_back() {
    let home = tempfile::tempdir().unwrap();
    let mut compositor = Compositor::new(Some(ext_protocol()));
    let mut job = started(&mut compositor, home.path());
    let ready = job.expect("ready");
    assert_eq!(ready["count"], 0);
    assert_eq!(ready["paused"], false);
    assert_eq!(ready["imported"], false);

    // Text, from an app that offers several types: plain text is read.
    let hello = b"hello\n  world";
    compositor.copy(
        &["text/html", "UTF8_STRING", "text/plain;charset=utf-8"],
        &[("UTF8_STRING", hello), ("text/plain;charset=utf-8", hello)],
        Duration::ZERO,
    );
    let text = job.expect("added")["item"].clone();
    assert_eq!(text["id"], 1);
    assert_eq!(text["kind"], "text");
    assert_eq!(text["mime"], "text/plain;charset=utf-8");
    assert_eq!(text["preview"], "hello world");
    assert_eq!(text["size"], hello.len());
    assert!(text["time"].as_u64().unwrap() > 1_700_000_000);
    assert_eq!(compositor.asked(), ["text/plain;charset=utf-8"]);

    // An image.
    compositor.copy(&["image/png"], &[("image/png", &PNG)], Duration::ZERO);
    let image = job.expect("added")["item"].clone();
    assert_eq!(image["id"], 2);
    assert_eq!(image["kind"], "image");
    assert_eq!(
        (image["width"].clone(), image["height"].clone()),
        (json!(3), json!(2))
    );
    assert_eq!(image["preview"], "PNG 3×2");

    // The same text again moves its entry to the top.
    compositor.copy_text("hello\n  world");
    assert_eq!(job.expect("added")["item"]["id"], 1);
    assert_eq!(ids(&job.items()), [1, 2]);

    // The image back on the clipboard, under its own type, and pasted.
    let asked = compositor.asked().len();
    job.send(json!({"copy": 2}));
    assert_eq!(job.expect("added")["item"]["id"], 2);
    // Its own content coming back as a new clipboard is not stored again,
    // nor even read.
    job.quiet();
    assert_eq!(compositor.asked().len(), asked);
    assert_eq!(compositor.job_types().unwrap(), ["image/png"]);
    let pasted = compositor.paste("image/png", 4096, Duration::ZERO);
    assert_eq!(pasted.recv_timeout(Duration::from_secs(5)).unwrap(), PNG);

    // A calculator answer: kept, and on the clipboard under every text type.
    job.send(json!({"copyText": "42"}));
    let answer = job.expect("added")["item"].clone();
    assert_eq!(
        (answer["id"].clone(), answer["preview"].clone()),
        (json!(3), json!("42"))
    );
    job.quiet();
    assert_eq!(compositor.job_types().unwrap(), TEXT_TYPES);
    let pasted = compositor.paste("STRING", 4096, Duration::ZERO);
    assert_eq!(pasted.recv_timeout(Duration::from_secs(5)).unwrap(), b"42");

    // Another app copies: the job lets go, and keeps the new content.
    compositor.copy_text("after");
    assert_eq!(job.expect("added")["item"]["preview"], "after");
    assert_eq!(ids(&job.items()), [4, 3, 2, 1]);

    let folder = home.path().join("skua/clipboard");
    assert_eq!(mode(&folder), 0o700);
    for name in ["index.json", "1.txt", "2.png", "3.txt", "4.txt"] {
        assert_eq!(mode(&folder.join(name)), 0o600, "{name}");
    }

    job.send(json!({"delete": 2}));
    assert_eq!(job.expect("removed")["id"], 2);
    assert!(!folder.join("2.png").exists());
    job.send(json!({"delete": 2}));
    job.expect("error");
    job.send(json!({"clear": true}));
    job.expect("cleared");
    assert!(job.items().is_empty());
    assert_eq!(
        std::fs::read_dir(&folder).unwrap().count(),
        1,
        "only the index"
    );
    job.send(json!({"frobnicate": 1}));
    job.expect("error");
    assert_eq!(job.end(), Some(0));
}

#[test]
fn leaves_out_secrets_and_what_it_cannot_keep() {
    let home = tempfile::tempdir().unwrap();
    let mut compositor = Compositor::new(Some(ext_protocol()));
    let mut job = started(&mut compositor, home.path());
    job.expect("ready");

    // A password: only the hint is read, never the password.
    compositor.copy(
        &["text/plain;charset=utf-8", "x-kde-passwordManagerHint"],
        &[
            ("text/plain;charset=utf-8", b"hunter2"),
            ("x-kde-passwordManagerHint", b"secret"),
        ],
        Duration::ZERO,
    );
    assert_eq!(job.expect("skipped")["reason"], "secret");
    assert_eq!(compositor.asked(), ["x-kde-passwordManagerHint"]);

    // A hint that does not say secret: the text is kept.
    compositor.copy(
        &["text/plain;charset=utf-8", "x-kde-passwordManagerHint"],
        &[
            ("text/plain;charset=utf-8", b"not a password"),
            ("x-kde-passwordManagerHint", b"public"),
        ],
        Duration::ZERO,
    );
    assert_eq!(job.expect("added")["item"]["preview"], "not a password");

    compositor.copy(&["text/html", "image/bmp"], &[], Duration::ZERO);
    assert_eq!(job.expect("skipped")["reason"], "unsupported");

    let big = vec![b'a'; (1 << 20) + 1];
    compositor.copy(
        &["text/plain;charset=utf-8"],
        &[("text/plain;charset=utf-8", &big)],
        Duration::ZERO,
    );
    assert_eq!(job.expect("skipped")["reason"], "too-big");
    let just = vec![b'b'; 1 << 20];
    compositor.copy(
        &["text/plain;charset=utf-8"],
        &[("text/plain;charset=utf-8", &just)],
        Duration::ZERO,
    );
    assert_eq!(job.expect("added")["item"]["size"], 1 << 20);

    // An app that takes 3 s to hand over its content: given up after 2 s,
    // and the job answers in the meantime.
    let asked = Instant::now();
    compositor.copy(
        &["text/plain;charset=utf-8"],
        &[("text/plain;charset=utf-8", b"slow")],
        Duration::from_secs(3),
    );
    std::thread::sleep(Duration::from_millis(100));
    assert_eq!(job.items().len(), 2);
    assert!(asked.elapsed() < Duration::from_secs(1));
    assert_eq!(job.expect("skipped")["reason"], "timeout");
    let waited = asked.elapsed();
    assert!(waited >= Duration::from_secs(2) && waited < Duration::from_millis(2800));

    // Paused: nothing is read or kept.
    job.send(json!({"pause": true}));
    assert_eq!(job.expect("paused")["paused"], true);
    let before = compositor.asked().len();
    compositor.copy_text("while paused");
    job.quiet();
    assert_eq!(compositor.asked().len(), before);
    job.send(json!({"copyText": "also while paused"}));
    job.quiet();
    assert_eq!(compositor.job_types().unwrap(), TEXT_TYPES);
    job.send(json!({"pause": false}));
    assert_eq!(job.expect("paused")["paused"], false);
    compositor.copy_text("after the pause");
    assert_eq!(job.expect("added")["item"]["preview"], "after the pause");
    assert_eq!(job.items().len(), 3);
}

#[test]
fn a_hint_in_another_spelling_and_a_bad_command_give_nothing_away() {
    let home = tempfile::tempdir().unwrap();
    let mut compositor = Compositor::new(Some(ext_protocol()));
    let mut job = started(&mut compositor, home.path());
    job.expect("ready");

    // Type names are not case-sensitive: this is a password too.
    compositor.copy(
        &["text/plain;charset=utf-8", "X-KDE-PasswordManagerHint"],
        &[
            ("text/plain;charset=utf-8", b"hunter2"),
            ("X-KDE-PasswordManagerHint", b"secret"),
        ],
        Duration::ZERO,
    );
    assert_eq!(job.expect("skipped")["reason"], "secret");
    assert_eq!(compositor.asked(), ["X-KDE-PasswordManagerHint"]);

    // The bar logs error messages: a command that cannot be used is named by
    // its keys, without the text it carries.
    job.send(json!({"copyText": "hunter2", "extra": true}));
    let error = job.expect("error");
    let message = error["message"].as_str().unwrap();
    assert!(message.contains("copyText"), "{message}");
    assert!(!message.contains("hunter2"), "{message}");
    job.send(json!({"copyText": 5}));
    assert_eq!(
        job.expect("error")["message"],
        "unknown command: {copyText}"
    );
    assert!(job.items().is_empty());
}

#[test]
fn an_image_is_kept_only_if_its_bytes_are_one() {
    let home = tempfile::tempdir().unwrap();
    let mut compositor = Compositor::new(Some(ext_protocol()));
    let job = started(&mut compositor, home.path());
    job.expect("ready");

    // Anything can be offered as a PNG: a drawing with scripts in it, say.
    let svg: &[u8] = b"<svg xmlns=\"http://www.w3.org/2000/svg\"><script>1</script></svg>";
    compositor.copy(&["image/png"], &[("image/png", svg)], Duration::ZERO);
    assert_eq!(job.expect("skipped")["reason"], "unsupported");

    // A real image is kept under its format's own name, whatever it was
    // called and however that was spelled.
    compositor.copy(&["IMAGE/PNG"], &[("IMAGE/PNG", &PNG)], Duration::ZERO);
    let image = job.expect("added")["item"].clone();
    assert_eq!(image["mime"], "image/png");
    let jpeg: &[u8] = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01";
    compositor.copy(&["image/png"], &[("image/png", jpeg)], Duration::ZERO);
    let image = job.expect("added")["item"].clone();
    assert_eq!(
        (&image["mime"], &image["preview"]),
        (&json!("image/jpeg"), &json!("JPEG"))
    );

    // Only the two real images are on disk, each under its own extension.
    let folder = home.path().join("skua/clipboard");
    let mut files: Vec<String> = std::fs::read_dir(&folder)
        .unwrap()
        .map(|entry| entry.unwrap().file_name().into_string().unwrap())
        .collect();
    files.sort();
    assert_eq!(files, ["1.png", "2.jpg", "index.json"]);
    assert_eq!(std::fs::read(folder.join("1.png")).unwrap(), PNG);
}

#[test]
fn a_flood_of_copies_does_not_push_the_history_out() {
    let home = tempfile::tempdir().unwrap();
    let mut compositor = Compositor::new(Some(ext_protocol()));
    let mut job = started(&mut compositor, home.path());
    job.expect("ready");

    // Setting the clipboard to what is already at the top costs nothing.
    for _ in 0..40 {
        compositor.copy_text("the same again");
        assert_eq!(job.expect("added")["item"]["id"], 1);
    }

    // New entries: a burst of 30 at most, then one every 2 s. 45 in a row
    // are far faster than that, so some are refused, unread.
    let (mut kept, mut refused) = (0, 0);
    for n in 0..45 {
        compositor.copy_text(&format!("flood {n}"));
        let line = job.lines.recv_timeout(Duration::from_secs(5)).unwrap();
        match line["event"].as_str() {
            Some("added") => kept += 1,
            Some("skipped") => {
                assert_eq!(line["reason"], "too-fast");
                refused += 1;
            }
            _ => panic!("unexpected line {line}"),
        }
    }
    assert!(kept >= 29, "a normal burst is kept: {kept}");
    assert!(refused >= 1, "the flood is not: {kept} kept");
    let items = job.items();
    assert_eq!(items.len(), kept + 1);
    assert_eq!(items.last().unwrap()["preview"], "the same again");
}

#[test]
fn more_pastes_than_it_answers_at_once_get_nothing() {
    let home = tempfile::tempdir().unwrap();
    let mut compositor = Compositor::new(Some(ext_protocol()));
    let mut job = started(&mut compositor, home.path());
    job.expect("ready");

    // Far more than a pipe holds, so a paste nobody reads stays open.
    let text = "a".repeat(1 << 20);
    job.send(json!({"copyText": text}));
    job.expect("added");
    let stuck: Vec<_> = (0..32)
        .map(|_| compositor.paste("text/plain", 1, Duration::from_secs(1)))
        .collect();
    std::thread::sleep(Duration::from_millis(200));

    let one_more = compositor.paste("text/plain", 4096, Duration::ZERO);
    let got = one_more.recv_timeout(Duration::from_secs(5)).unwrap();
    assert!(got.is_empty(), "{} bytes arrived", got.len());
    assert_eq!(job.items().len(), 1, "the job still answers");
    drop(stuck);
}

#[test]
fn a_slow_paste_does_not_hold_up_the_job() {
    let home = tempfile::tempdir().unwrap();
    let mut compositor = Compositor::new(Some(ext_protocol()));
    let mut job = started(&mut compositor, home.path());
    job.expect("ready");

    // 3 MB of image, far more than a pipe holds.
    let mut image = PNG.to_vec();
    image.extend((0..3_000_000u32).map(|n| n as u8));
    compositor.copy(&["image/png"], &[("image/png", &image)], Duration::ZERO);
    let id = job.expect("added")["item"]["id"].clone();
    job.send(json!({"copy": id}));
    job.expect("added");

    // Read in 16 KiB pieces with a pause between: over a second in all.
    let started = Instant::now();
    let pasted = compositor.paste("image/png", 16 * 1024, Duration::from_millis(5));
    std::thread::sleep(Duration::from_millis(100));
    assert_eq!(job.items().len(), 1);
    assert!(
        started.elapsed() < Duration::from_millis(500),
        "answered during the paste"
    );
    let got = pasted.recv_timeout(Duration::from_secs(20)).unwrap();
    assert!(started.elapsed() > Duration::from_millis(500));
    assert!(got == image, "the whole image arrived intact");
}

#[test]
fn the_history_survives_a_restart() {
    let home = tempfile::tempdir().unwrap();
    {
        let mut compositor = Compositor::new(Some(ext_protocol()));
        let mut job = started(&mut compositor, home.path());
        job.expect("ready");
        for text in ["one", "two", "three"] {
            compositor.copy_text(text);
            job.expect("added");
        }
        compositor.copy_text("one");
        job.expect("added");
        job.send(json!({"pause": true}));
        job.expect("paused");
        assert_eq!(ids(&job.items()), [1, 3, 2]);
        assert_eq!(job.end(), Some(0));
    }
    let mut compositor = Compositor::new(Some(ext_protocol()));
    let mut job = started(&mut compositor, home.path());
    let ready = job.expect("ready");
    assert_eq!(ready["count"], 3);
    assert_eq!(ready["paused"], true);
    let items = job.items();
    assert_eq!(ids(&items), [1, 3, 2]);
    assert_eq!(items[0]["preview"], "one");
    // Copying an entry from before the restart.
    job.send(json!({"copy": 2}));
    job.expect("added");
    let pasted = compositor.paste("text/plain", 4096, Duration::ZERO);
    assert_eq!(pasted.recv_timeout(Duration::from_secs(5)).unwrap(), b"two");
}

#[test]
fn imports_a_cliphist_history_once() {
    // It needs a real cliphist to fill a history to import.
    if Command::new("cliphist").arg("version").output().is_err() {
        eprintln!("cliphist is not installed: skipped");
        return;
    }
    let home = tempfile::tempdir().unwrap();
    let cliphist_store = |data: &[u8]| {
        let mut child = Command::new("cliphist")
            .arg("-db-path")
            .arg(home.path().join("cliphist-db"))
            .arg("-config-path")
            .arg(home.path().join("no-config"))
            .arg("store")
            .env_remove("CLIPBOARD_STATE")
            .stdin(Stdio::piped())
            .spawn()
            .expect("cliphist is installed");
        child.stdin.take().unwrap().write_all(data).unwrap();
        assert!(child.wait().unwrap().success());
    };
    cliphist_store(b"old one");
    cliphist_store(&PNG);
    cliphist_store(b"old two");

    let mut compositor = Compositor::new(Some(ext_protocol()));
    let mut job = started(&mut compositor, home.path());
    job.expect("ready");
    compositor.copy_text("old two");
    job.expect("added");
    job.send(json!({"import": "cliphist"}));
    assert_eq!(
        job.expect("imported")["count"],
        2,
        "the copy already kept is left out"
    );
    let items = job.expect("items")["items"].as_array().unwrap().clone();
    let shown: Vec<_> = items
        .iter()
        .map(|item| {
            (
                item["kind"].as_str().unwrap(),
                item["preview"].as_str().unwrap(),
                item["time"].as_u64().unwrap() > 0,
            )
        })
        .collect();
    assert_eq!(
        shown,
        [
            ("text", "old two", true),
            ("image", "PNG 3×2", false),
            ("text", "old one", false)
        ],
        "below what is newer, newest first"
    );
    job.send(json!({"copy": items[1]["id"]}));
    job.expect("added");
    let pasted = compositor.paste("image/png", 4096, Duration::ZERO);
    assert_eq!(pasted.recv_timeout(Duration::from_secs(5)).unwrap(), PNG);
    assert_eq!(job.end(), Some(0));

    let mut compositor = Compositor::new(Some(ext_protocol()));
    let job = started(&mut compositor, home.path());
    let ready = job.expect("ready");
    assert_eq!(
        (ready["count"].clone(), ready["imported"].clone()),
        (json!(3), json!(true))
    );
}

#[test]
fn works_with_the_older_wlroots_protocol() {
    let home = tempfile::tempdir().unwrap();
    let mut compositor = Compositor::new(Some(wlr_protocol()));
    let mut job = started(&mut compositor, home.path());
    job.expect("ready");
    compositor.copy_text("through wlr");
    assert_eq!(job.expect("added")["item"]["preview"], "through wlr");
    job.send(json!({"copy": 1}));
    job.expect("added");
    let pasted = compositor.paste("UTF8_STRING", 4096, Duration::ZERO);
    assert_eq!(
        pasted.recv_timeout(Duration::from_secs(5)).unwrap(),
        b"through wlr"
    );
}

#[test]
fn without_data_control_the_job_ends_with_status_3() {
    let home = tempfile::tempdir().unwrap();
    let mut compositor = Compositor::new(None);
    let job = started(&mut compositor, home.path());
    let error = job.expect("error");
    assert!(error["message"]
        .as_str()
        .unwrap()
        .contains("ext_data_control_manager_v1"));
    let mut job = job;
    let started = Instant::now();
    let status = loop {
        if let Some(status) = job.child.try_wait().unwrap() {
            break status;
        }
        assert!(started.elapsed() < Duration::from_secs(5));
        std::thread::sleep(Duration::from_millis(10));
    };
    assert_eq!(status.code(), Some(3));
}
