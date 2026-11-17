//! `skua-helper clipboard`: Skua's clipboard history.
//!
//! Watches the clipboard (wayland.rs), keeps what is copied in a history on
//! disk (store.rs), and puts an entry back on the clipboard when the launcher
//! picks one; this job then answers every paste itself, so nothing else
//! (wl-copy, cliphist) is needed. Text and images are kept: plain text when an
//! app offers it, else a PNG, JPEG, WebP or GIF (content.rs; what an app calls
//! an image is kept only if its first bytes are one). Not kept: a password a
//! password manager marks secret, anything over 1 MB of text or 20 MB of
//! image, content an app takes over 2 s to hand over, more than a burst of 30
//! new entries at a time (rate.rs), and anything at all while paused. At most
//! 500 entries and 500 MB; a new one beyond that deletes the oldest. Copying
//! something already in the history moves it to the top.
//!
//! From the bar (stdin), one object per line:
//!
//! ```text
//! {"list":true}          answer with the whole history ("items")
//! {"copy":ID}            put an entry on the clipboard; it moves to the top
//! {"copyText":"..."}     put this text on the clipboard, and in the history
//! {"delete":ID}          delete an entry
//! {"clear":true}         delete every entry
//! {"pause":true|false}   stop or go on keeping what is copied; kept across restarts
//! {"import":"cliphist"}  add the newest 500 entries of a cliphist history (import.rs)
//! ```
//!
//! To the bar (stdout), after the hello line (protocol.rs):
//!
//! ```text
//! {"event":"ready","count":12,"paused":false,"imported":false}
//!     watching; "imported": a cliphist import has been done (or found nothing)
//! {"event":"items","items":[ITEM, ...]}   the history, newest first
//! {"event":"added","item":ITEM}   this entry is now at the top: new, or moved there
//!                                 (copied again, or picked with "copy")
//! {"event":"removed","id":7}      deleted, by "delete" or to stay within 500
//! {"event":"cleared"}
//! {"event":"paused","paused":true}
//! {"event":"skipped","reason":R}  something copied was not kept: R is "secret",
//!                                 "too-big", "unsupported" (no text or image),
//!                                 "timeout" (the app took over 2 s) or
//!                                 "too-fast" (too many new entries at once)
//! {"event":"imported","count":40} entries added by an import
//! {"event":"error","message":"..."}   something failed; the job goes on
//!
//! ITEM: {"id":7,"kind":"text"|"image","mime":"image/png","preview":"PNG 1920×1080",
//!        "time":1763380000,"size":48211,"width":1920,"height":1080}
//!     preview: the start of a text on one line, or an image's format and size;
//!     time: seconds since 1970 (0 when imported); size: bytes; width and
//!     height only for a PNG or GIF.
//! ```
//!
//! While paused, "copyText" still puts its text on the clipboard but does not
//! keep it. A compositor without data control (ext or wlr) gets an error line
//! and exit status 3. The job ends when stdin closes; what it put on the
//! clipboard goes with it, as the clipboard always goes with the app that set
//! it.

mod content;
mod import;
mod pipe;
mod rate;
mod store;
mod wayland;

use std::collections::HashMap;
use std::os::fd::{AsFd, OwnedFd};
use std::process::ExitCode;
use std::rc::Rc;
use std::time::{Duration, Instant, SystemTime};

use calloop::generic::Generic;
use calloop::timer::{TimeoutAction, Timer};
use calloop::{
    channel, EventLoop, Interest, LoopHandle, LoopSignal, Mode, PostAction, RegistrationToken,
};
use calloop_wayland_source::WaylandSource;
use serde::Deserialize;
use serde_json::{json, Value};
use wayland_client::QueueHandle;

use crate::protocol::{self, emit};
use content::{Kind, TEXT_TYPES};
use import::{Cliphist, Old};
use pipe::{Incoming, Outgoing, Pump};
use rate::Allowance;
use store::{Added, Store};
use wayland::{Clipboard, ConnectError, Offer, Source};

/// The longest an app may take to hand over what it copied.
const READ_LIMIT: Duration = Duration::from_secs(2);

/// A paste whose app reads nothing for this long is given up.
const PASTE_LIMIT: Duration = Duration::from_secs(10);

/// A paste is given up after this long even when its app keeps taking a
/// little: nothing on one machine needs a minute.
const PASTE_LONGEST: Duration = Duration::from_secs(60);

/// The most pastes answered at the same time. Each holds a pipe open, and an
/// app could ask for thousands and read none.
const MAX_PASTES: usize = 32;

/// The password hint is one short word.
const HINT_LIMIT: usize = 64;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
enum Command {
    List(serde::de::IgnoredAny),
    Copy(u64),
    CopyText(String),
    Delete(u64),
    Clear(bool),
    Pause(bool),
    Import(String),
}

/// What an import thread hands to the job.
enum Imported {
    Entry(Old),
    Done(Result<(), String>),
}

/// Content an app copied, being read.
struct Capture {
    /// Tells this capture's timer from a later one's.
    serial: u64,
    offer: Offer,
    types: Vec<String>,
    /// None while the password hint is read, then the type being read.
    reading: Option<(Kind, String)>,
    incoming: Incoming,
    pipe: RegistrationToken,
    timer: RegistrationToken,
}

/// Content this job put on the clipboard.
struct Owned {
    source: Source,
    data: Rc<Vec<u8>>,
}

/// One paste being answered.
struct Paste {
    outgoing: Outgoing,
    /// When the app last took some of it.
    moved: Instant,
    started: Instant,
    pipe: RegistrationToken,
    timer: RegistrationToken,
}

pub struct Job {
    store: Store,
    clipboard: Clipboard,
    qh: QueueHandle<Job>,
    handle: LoopHandle<'static, Job>,
    signal: LoopSignal,
    capture: Option<Capture>,
    serial: u64,
    owned: Option<Owned>,
    pastes: HashMap<u64, Paste>,
    importing: Option<usize>,
    allowance: Allowance,
    /// The job is ending because of a failure.
    failed: bool,
}

pub fn run() -> ExitCode {
    protocol::hello("clipboard");
    let Some(dir) = store::default_dir() else {
        protocol::error("neither XDG_STATE_HOME nor HOME is set");
        return ExitCode::FAILURE;
    };
    let store = match Store::open(dir) {
        Ok(store) => store,
        Err(err) => {
            protocol::error(format!("cannot open the clipboard history: {err}"));
            return ExitCode::FAILURE;
        }
    };
    let (connection, queue, clipboard) = match wayland::connect() {
        Ok(connected) => connected,
        Err(ConnectError::NoProtocol) => {
            protocol::error(
                "the compositor offers no clipboard control \
                 (ext_data_control_manager_v1 or zwlr_data_control_manager_v1)",
            );
            return ExitCode::from(3);
        }
        Err(ConnectError::Failed(message)) => {
            protocol::error(message);
            return ExitCode::FAILURE;
        }
    };
    let mut event_loop = match EventLoop::<Job>::try_new() {
        Ok(event_loop) => event_loop,
        Err(err) => {
            protocol::error(format!("cannot start: {err}"));
            return ExitCode::FAILURE;
        }
    };
    let handle = event_loop.handle();
    let qh = queue.handle();
    if let Err(err) = WaylandSource::new(connection, queue).insert(handle.clone()) {
        protocol::error(format!("cannot start: {}", err.error));
        return ExitCode::FAILURE;
    }

    // The bar's commands arrive on stdin. A plain thread reads them and hands
    // each one to the loop; when stdin closes, so does the channel.
    let (commands, received) = channel::channel::<Value>();
    std::thread::spawn(move || {
        protocol::read_commands(|command| {
            let _ = commands.send(command);
        });
    });
    let inserted = handle.insert_source(received, |event, _, job: &mut Job| match event {
        channel::Event::Msg(command) => job.command(command),
        channel::Event::Closed => job.signal.stop(),
    });
    if let Err(err) = inserted {
        protocol::error(format!("cannot start: {}", err.error));
        return ExitCode::FAILURE;
    }

    let mut job = Job {
        store,
        clipboard,
        qh,
        handle,
        signal: event_loop.get_signal(),
        capture: None,
        serial: 0,
        owned: None,
        pastes: HashMap::new(),
        importing: None,
        allowance: Allowance::new(Instant::now()),
        failed: false,
    };
    emit(json!({
        "event": "ready",
        "count": job.store.len(),
        "paused": job.store.paused(),
        "imported": job.store.imported(),
    }));
    if let Err(err) = event_loop.run(None, &mut job, |_| {}) {
        protocol::error(format!("lost the compositor: {err}"));
        return ExitCode::FAILURE;
    }
    if job.failed {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map_or(0, |since| since.as_secs())
}

fn skipped(reason: &str) {
    emit(json!({"event": "skipped", "reason": reason}));
}

fn added(added: Added) {
    emit(json!({"event": "added", "item": added.item}));
    for id in added.dropped {
        emit(json!({"event": "removed", "id": id}));
    }
}

impl Job {
    fn command(&mut self, command: Value) {
        let Ok(parsed) = Command::deserialize(&command) else {
            protocol::error(format!("unknown command: {}", protocol::shape(&command)));
            return;
        };
        match parsed {
            Command::List(_) => self.list(),
            Command::Copy(id) => self.copy(id),
            Command::CopyText(text) => self.copy_text(text),
            Command::Delete(id) => match self.store.remove(id) {
                Ok(true) => emit(json!({"event": "removed", "id": id})),
                Ok(false) => protocol::error(format!("no clipboard entry {id}")),
                Err(err) => protocol::error(format!("cannot delete entry {id}: {err}")),
            },
            Command::Clear(true) => match self.store.clear() {
                Ok(()) => emit(json!({"event": "cleared"})),
                Err(err) => protocol::error(format!("cannot clear the history: {err}")),
            },
            Command::Clear(false) => {}
            Command::Pause(paused) => {
                if paused {
                    self.drop_capture(true, true);
                }
                match self.store.set_paused(paused) {
                    Ok(()) => emit(json!({"event": "paused", "paused": paused})),
                    Err(err) => protocol::error(format!("cannot save the pause: {err}")),
                }
            }
            Command::Import(from) if from == "cliphist" => self.import(),
            Command::Import(from) => protocol::error(format!("cannot import from {from:?}")),
        }
    }

    fn list(&self) {
        let items: Vec<_> = self.store.items().collect();
        emit(json!({"event": "items", "items": items}));
    }

    fn copy(&mut self, id: u64) {
        let Some(item) = self.store.item(id) else {
            protocol::error(format!("no clipboard entry {id}"));
            return;
        };
        let (kind, mime) = (item.kind, item.mime.clone());
        match self.store.read(id) {
            Ok(data) => self.own(kind, &mime, data),
            Err(err) => {
                protocol::error(format!("cannot read entry {id}: {err}"));
                return;
            }
        }
        match self.store.touch(id, now()) {
            Ok(Some(item)) => emit(json!({"event": "added", "item": item})),
            Ok(None) => {}
            Err(err) => protocol::error(format!("cannot save the history: {err}")),
        }
    }

    fn copy_text(&mut self, text: String) {
        let data = text.into_bytes();
        if self.store.paused() {
            // Kept out of the history, like anything copied while paused.
        } else if data.len() > Kind::Text.limit() {
            skipped("too-big");
        } else if !data.is_empty() {
            match self.store.add(Kind::Text, TEXT_TYPES[0], &data, now()) {
                Ok(new) => added(new),
                Err(err) => protocol::error(format!("cannot save the history: {err}")),
            }
        }
        self.own(Kind::Text, TEXT_TYPES[0], data);
    }

    /// Puts content on the clipboard. Text goes under every plain-text name,
    /// an image under its own type.
    fn own(&mut self, kind: Kind, mime: &str, data: Vec<u8>) {
        let image = [mime];
        let types: &[&str] = match kind {
            Kind::Text => &TEXT_TYPES,
            Kind::Image => &image,
        };
        let source = self.clipboard.offer(types, &self.qh);
        let previous = self.owned.replace(Owned {
            source,
            data: Rc::new(data),
        });
        // After set_selection, so the clipboard is never empty in between.
        // Pastes already under way keep their own copy of the data.
        if let Some(previous) = previous {
            previous.source.destroy();
        }
    }

    // ── Watching ─────────────────────────────────────────────────────────

    /// The clipboard changed (wayland.rs).
    fn selection(&mut self, offer: Option<Offer>) {
        // Whatever was being read is out of date now.
        self.drop_capture(true, true);
        let Some(offer) = offer else { return };
        // Content this job put there itself is already in the history.
        if self.owned.is_some() || self.store.paused() {
            offer.destroy();
            return;
        }
        // Too many new entries in a short time (rate.rs): this one is not
        // even read.
        if !self.allowance.any(Instant::now()) {
            offer.destroy();
            skipped("too-fast");
            return;
        }
        let types = offer.types();
        // The password hint first, if the app offers one; else the content.
        let (kind, name) = match content::secret_hint(&types) {
            Some(hint) => (None, hint),
            None => match content::choose(&types) {
                Some((kind, name)) => (Some(kind), name),
                None => {
                    offer.destroy();
                    skipped("unsupported");
                    return;
                }
            },
        };
        let reading = kind.map(|kind| (kind, name.to_owned()));
        let limit = kind.map_or(HINT_LIMIT, Kind::limit);
        self.serial += 1;
        let serial = self.serial;
        let timer =
            self.handle
                .insert_source(Timer::from_duration(READ_LIMIT), move |_, _, job| {
                    job.read_timed_out(serial);
                    TimeoutAction::Drop
                });
        let Ok(timer) = timer else {
            offer.destroy();
            protocol::error("cannot start a timer");
            return;
        };
        match self.receive(&offer, name) {
            Ok(pipe) => {
                self.capture = Some(Capture {
                    serial,
                    offer,
                    types,
                    reading,
                    incoming: Incoming::new(limit),
                    pipe,
                    timer,
                });
            }
            Err(err) => {
                self.handle.remove(timer);
                offer.destroy();
                protocol::error(format!("cannot read the clipboard: {err}"));
            }
        }
    }

    /// Asks the app for its content as `name`, through a pipe the loop
    /// watches.
    fn receive(&self, offer: &Offer, name: &str) -> std::io::Result<RegistrationToken> {
        let (reader, writer) = std::io::pipe()?;
        offer.receive(name, writer.as_fd());
        // The request holds its own copy of the write end. Without closing
        // this one, the pipe would never report the end of the content.
        drop(writer);
        let reader = OwnedFd::from(reader);
        // Only the read end: the app's end stays an ordinary blocking pipe.
        rustix::io::ioctl_fionbio(&reader, true)?;
        self.handle
            .insert_source(
                Generic::new(reader, Interest::READ, Mode::Level),
                |_, pipe, job: &mut Job| Ok(job.readable(pipe)),
            )
            .map_err(|err| err.error.into())
    }

    fn readable(&mut self, pipe: &OwnedFd) -> PostAction {
        let Some(capture) = self.capture.as_mut() else {
            return PostAction::Remove;
        };
        match capture.incoming.pump(pipe) {
            Ok(Pump::Pending) => PostAction::Continue,
            Ok(Pump::TooBig) => {
                self.drop_capture(false, true);
                skipped("too-big");
                PostAction::Remove
            }
            Ok(Pump::Done) => {
                self.read_done();
                PostAction::Remove
            }
            Err(err) => {
                self.drop_capture(false, true);
                protocol::error(format!("cannot read the clipboard: {err}"));
                PostAction::Remove
            }
        }
    }

    /// One read ended: the password hint, after which the content is read,
    /// or the content, which is stored.
    fn read_done(&mut self) {
        let Some(mut capture) = self.capture.take() else {
            return;
        };
        let data = std::mem::take(&mut capture.incoming.data);
        match capture.reading.take() {
            None => {
                if content::is_secret(&data) {
                    self.handle.remove(capture.timer);
                    capture.offer.destroy();
                    skipped("secret");
                    return;
                }
                let Some((kind, name)) = content::choose(&capture.types) else {
                    self.handle.remove(capture.timer);
                    capture.offer.destroy();
                    skipped("unsupported");
                    return;
                };
                let name = name.to_owned();
                match self.receive(&capture.offer, &name) {
                    Ok(pipe) => {
                        capture.pipe = pipe;
                        capture.incoming = Incoming::new(kind.limit());
                        capture.reading = Some((kind, name));
                        self.capture = Some(capture);
                    }
                    Err(err) => {
                        self.handle.remove(capture.timer);
                        capture.offer.destroy();
                        protocol::error(format!("cannot read the clipboard: {err}"));
                    }
                }
            }
            Some((kind, name)) => {
                self.handle.remove(capture.timer);
                capture.offer.destroy();
                if data.is_empty() {
                    return;
                }
                // An app can call anything an image. Only what starts as a
                // PNG, JPEG, WebP or GIF is kept, under that format's name.
                let mime = match kind {
                    Kind::Text => name.as_str(),
                    Kind::Image => match content::sniff_image(&data) {
                        Some(mime) => mime,
                        None => {
                            skipped("unsupported");
                            return;
                        }
                    },
                };
                // Copying what is already at the top changes nothing and
                // costs nothing: some apps set the clipboard again and again.
                let top = self.store.items().next().map(|item| item.id);
                match self.store.add(kind, mime, &data, now()) {
                    Ok(new) => {
                        if Some(new.item.id) != top {
                            self.allowance.spend(Instant::now());
                        }
                        added(new);
                    }
                    Err(err) => protocol::error(format!("cannot save the history: {err}")),
                }
            }
        }
    }

    fn read_timed_out(&mut self, serial: u64) {
        if self
            .capture
            .as_ref()
            .is_some_and(|capture| capture.serial == serial)
        {
            self.drop_capture(true, false);
            skipped("timeout");
        }
    }

    /// Stops reading. `pipe` and `timer` say which of its two sources to
    /// remove: not the one whose own callback is running, which removes
    /// itself.
    fn drop_capture(&mut self, pipe: bool, timer: bool) {
        if let Some(capture) = self.capture.take() {
            if pipe {
                self.handle.remove(capture.pipe);
            }
            if timer {
                self.handle.remove(capture.timer);
            }
            capture.offer.destroy();
        }
    }

    /// The compositor withdrew the clipboard device (wayland.rs).
    fn finished(&mut self) {
        protocol::error("the compositor closed the clipboard");
        self.failed = true;
        self.signal.stop();
    }

    // ── Answering pastes ─────────────────────────────────────────────────

    /// An app pastes what this job put on the clipboard (wayland.rs).
    fn paste(&mut self, source: &Source, pipe: OwnedFd) {
        let Some(owned) = self.owned.as_ref().filter(|owned| owned.source == *source) else {
            // An older one: closing the pipe gives the app nothing.
            return;
        };
        if self.pastes.len() >= MAX_PASTES {
            // Closing the pipe gives this one nothing; the others go on.
            return;
        }
        if let Err(err) = rustix::io::ioctl_fionbio(&pipe, true) {
            protocol::error(format!("cannot answer a paste: {err}"));
            return;
        }
        self.serial += 1;
        let serial = self.serial;
        let outgoing = Outgoing::new(Rc::clone(&owned.data));
        let writable = self.handle.insert_source(
            Generic::new(pipe, Interest::WRITE, Mode::Level),
            move |_, pipe, job: &mut Job| Ok(job.writable(serial, pipe)),
        );
        let Ok(pipe) = writable else {
            protocol::error("cannot answer a paste");
            return;
        };
        let timer = self
            .handle
            .insert_source(Timer::from_duration(PASTE_LIMIT), move |_, _, job| {
                job.paste_timer(serial)
            });
        let Ok(timer) = timer else {
            self.handle.remove(pipe);
            protocol::error("cannot start a timer");
            return;
        };
        let now = Instant::now();
        let paste = Paste {
            outgoing,
            moved: now,
            started: now,
            pipe,
            timer,
        };
        self.pastes.insert(serial, paste);
    }

    fn writable(&mut self, serial: u64, pipe: &OwnedFd) -> PostAction {
        let Some(paste) = self.pastes.get_mut(&serial) else {
            return PostAction::Remove;
        };
        paste.moved = Instant::now();
        // Done, or an error: the app took it all, or went away.
        if let Ok(Pump::Pending) = paste.outgoing.pump(pipe) {
            return PostAction::Continue;
        }
        if let Some(paste) = self.pastes.remove(&serial) {
            self.handle.remove(paste.timer);
        }
        PostAction::Remove
    }

    fn paste_timer(&mut self, serial: u64) -> TimeoutAction {
        let Some(paste) = self.pastes.get(&serial) else {
            return TimeoutAction::Drop;
        };
        let left = paste_time_left(paste.moved.elapsed(), paste.started.elapsed());
        if !left.is_zero() {
            return TimeoutAction::ToDuration(left);
        }
        if let Some(paste) = self.pastes.remove(&serial) {
            self.handle.remove(paste.pipe);
        }
        TimeoutAction::Drop
    }

    /// Another app copied something (wayland.rs).
    fn cancelled(&mut self, source: Source) {
        if self
            .owned
            .as_ref()
            .is_some_and(|owned| owned.source == source)
        {
            self.owned = None;
        }
        source.destroy();
    }

    // ── Importing ────────────────────────────────────────────────────────

    /// Reads cliphist in a thread of its own (it runs one cliphist process
    /// per entry) and stores what it hands over, one entry at a time.
    fn import(&mut self) {
        if self.importing.is_some() {
            protocol::error("an import is already running");
            return;
        }
        // A few entries in flight at most: images can be large.
        let (entries, received) = channel::sync_channel::<Imported>(4);
        let inserted = self
            .handle
            .insert_source(received, |event, _, job: &mut Job| {
                if let channel::Event::Msg(imported) = event {
                    job.imported(imported);
                }
            });
        if let Err(err) = inserted {
            protocol::error(format!("cannot import: {}", err.error));
            return;
        }
        self.importing = Some(0);
        let cliphist = Cliphist::from_env();
        std::thread::spawn(move || {
            let result = cliphist.read(store::MAX_ITEMS, |old| {
                entries.send(Imported::Entry(old)).is_ok()
            });
            let _ = entries.send(Imported::Done(result));
        });
    }

    fn imported(&mut self, imported: Imported) {
        let Some(count) = self.importing.as_mut() else {
            return;
        };
        match imported {
            Imported::Entry(old) => match self.store.add_old(old.kind, old.mime, &old.data) {
                Ok(Some(_)) => *count += 1,
                Ok(None) => {}
                Err(err) => protocol::error(format!("cannot save an imported entry: {err}")),
            },
            Imported::Done(result) => {
                let count = *count;
                self.importing = None;
                let saved = match result {
                    Ok(()) => self.store.set_imported(),
                    Err(message) => {
                        protocol::error(message);
                        self.store.save()
                    }
                };
                if let Err(err) = saved {
                    protocol::error(format!("cannot save the history: {err}"));
                }
                emit(json!({"event": "imported", "count": count}));
                self.list();
            }
        }
    }
}

/// How long a paste may still wait, given how long ago its app last took
/// some of it and how long ago it began. Zero: it is given up.
fn paste_time_left(idle: Duration, age: Duration) -> Duration {
    PASTE_LIMIT
        .saturating_sub(idle)
        .min(PASTE_LONGEST.saturating_sub(age))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_paste_is_given_up_when_idle_or_when_it_takes_too_long() {
        let s = Duration::from_secs;
        assert_eq!(paste_time_left(s(0), s(0)), s(10));
        assert_eq!(paste_time_left(s(4), s(30)), s(6));
        assert_eq!(paste_time_left(s(10), s(30)), Duration::ZERO);
        // An app that keeps taking a little is not waited for past a minute.
        assert_eq!(paste_time_left(s(1), s(55)), s(5));
        assert_eq!(paste_time_left(s(0), s(60)), Duration::ZERO);
        assert_eq!(paste_time_left(s(0), s(3600)), Duration::ZERO);
    }
}
