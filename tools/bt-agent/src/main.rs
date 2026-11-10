//! tern-bar-bt-agent: answers BlueZ's pairing questions for tern-bar.
//!
//! BlueZ, the Linux Bluetooth service, hands every question a pairing can
//! raise to a "pairing agent": a PIN to type, a passkey, "does the device show
//! 123456?", "may this device pair or connect?". Quickshell has no agent, so
//! tern-bar starts this program. It registers with BlueZ as the default agent
//! and passes each question to the bar as one line of JSON on stdout; the bar
//! shows it and writes the answer back as one line of JSON on stdin.
//!
//! To the bar (stdout), one object per line:
//!
//! ```text
//! {"event":"ready"}      registered with BlueZ: the questions come here now
//! {"event":"waiting"}    BlueZ is not running; registers as soon as it is
//! {"event":"request","id":7,"kind":KIND,"device":PATH,"address":ADDR, ...}
//!     KIND "pin"        type a PIN; answer {"id":7,"pin":"0000"} (1-16 characters)
//!          "passkey"    type a number; answer {"id":7,"passkey":123456}
//!          "confirm"    + "code":"012345": is it the number on the device?
//!          "authorize"  the device asks to pair with this computer
//!          "service"    + "uuid": the device asks to use a service
//!     a yes/no question is answered {"id":7,"accept":true}
//! {"event":"show","kind":"pin"|"passkey","device":PATH,"address":ADDR,"code":"012345","entered":3}
//!     type this code on the device itself; nothing to answer
//! {"event":"cancel"}     BlueZ withdrew its question (it waits one minute at most)
//! {"event":"error","message":"..."}   something failed; the program goes on
//! ```
//!
//! An answer without a value, or with an empty PIN, refuses. The program ends
//! when stdin closes (the bar quit or reloaded), and BlueZ forgets an agent
//! whose connection has gone.

use std::collections::HashMap;
use std::io::{BufRead, Write};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use futures_channel::oneshot;
use futures_lite::StreamExt;
use serde::Deserialize;
use serde_json::{json, Value};
use zbus::zvariant::{ObjectPath, OwnedObjectPath};
use zbus::{fdo, interface, proxy, Connection};

/// Where the agent lives on the bus. Any path works; BlueZ is told this one.
const AGENT_PATH: &str = "/org/ternbar/agent";

/// What the agent can do. "KeyboardDisplay" (it can show a code and have one
/// typed in) lets BlueZ use every pairing method, so any device can pair.
const CAPABILITY: &str = "KeyboardDisplay";

/// One answer from the bar.
#[derive(Deserialize)]
struct Answer {
    id: u64,
    pin: Option<String>,
    passkey: Option<u32>,
    accept: Option<bool>,
}

/// The errors BlueZ understands from an agent.
#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org.bluez.Error")]
enum AgentError {
    #[zbus(error)]
    ZBus(zbus::Error),
    Rejected(String),
    Canceled(String),
}

/// The questions waiting for an answer, by id.
type Waiting = Arc<Mutex<HashMap<u64, oneshot::Sender<Answer>>>>;

struct Agent {
    waiting: Waiting,
    next_id: AtomicU64,
}

/// Writes one line for the bar.
fn emit(line: Value) {
    let mut out = std::io::stdout().lock();
    // If the bar has gone, stdin has closed too and the program is about to
    // end, so a failed write needs nothing more.
    let _ = writeln!(out, "{line}");
    let _ = out.flush();
}

/// "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF" gives "AA:BB:CC:DD:EE:FF".
fn address_of(device: &ObjectPath<'_>) -> String {
    device
        .as_str()
        .rsplit('/')
        .next()
        .and_then(|last| last.strip_prefix("dev_"))
        .map(|address| address.replace('_', ":"))
        .unwrap_or_default()
}

impl Agent {
    /// Puts a question to the bar and waits for the answer.
    async fn ask(
        &self,
        kind: &str,
        device: &ObjectPath<'_>,
        extra: Value,
    ) -> Result<Answer, AgentError> {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let (sender, receiver) = oneshot::channel();
        self.waiting.lock().unwrap().insert(id, sender);
        let mut line = json!({
            "event": "request",
            "id": id,
            "kind": kind,
            "device": device.as_str(),
            "address": address_of(device),
        });
        if let (Value::Object(line), Value::Object(extra)) = (&mut line, extra) {
            line.extend(extra);
        }
        emit(line);
        // The sender is dropped when BlueZ withdraws the question (cancel_all).
        receiver
            .await
            .map_err(|_| AgentError::Canceled("The question was withdrawn".into()))
    }

    async fn ask_yes_no(
        &self,
        kind: &str,
        device: &ObjectPath<'_>,
        extra: Value,
    ) -> Result<(), AgentError> {
        match self.ask(kind, device, extra).await?.accept {
            Some(true) => Ok(()),
            _ => Err(AgentError::Rejected("Refused".into())),
        }
    }

    fn show(&self, kind: &str, device: &ObjectPath<'_>, code: String, entered: Option<u16>) {
        emit(json!({
            "event": "show",
            "kind": kind,
            "device": device.as_str(),
            "address": address_of(device),
            "code": code,
            "entered": entered,
        }));
    }

    /// Drops every question still waiting; each one ends as Canceled.
    fn cancel_all(&self) {
        self.waiting.lock().unwrap().clear();
    }
}

/// What BlueZ calls (org.bluez.Agent1, described in BlueZ's doc/org.bluez.Agent.rst).
/// zbus turns each name into the D-Bus one: request_pin_code is RequestPinCode.
#[interface(name = "org.bluez.Agent1")]
impl Agent {
    /// BlueZ no longer uses this agent because it is stopping. run() registers
    /// again when it is back.
    fn release(&self) {
        self.cancel_all();
        emit(json!({"event": "waiting"}));
    }

    async fn request_pin_code(&self, device: OwnedObjectPath) -> Result<String, AgentError> {
        let pin = self
            .ask("pin", &device, json!({}))
            .await?
            .pin
            .unwrap_or_default();
        // A Bluetooth PIN is 1 to 16 characters.
        if pin.is_empty() || pin.len() > 16 {
            return Err(AgentError::Rejected("No PIN".into()));
        }
        Ok(pin)
    }

    fn display_pin_code(&self, device: OwnedObjectPath, pincode: String) {
        self.show("pin", &device, pincode, None);
    }

    async fn request_passkey(&self, device: OwnedObjectPath) -> Result<u32, AgentError> {
        match self.ask("passkey", &device, json!({})).await?.passkey {
            Some(passkey) if passkey <= 999_999 => Ok(passkey),
            _ => Err(AgentError::Rejected("No passkey".into())),
        }
    }

    fn display_passkey(&self, device: OwnedObjectPath, passkey: u32, entered: u16) {
        self.show("passkey", &device, format!("{passkey:06}"), Some(entered));
    }

    async fn request_confirmation(
        &self,
        device: OwnedObjectPath,
        passkey: u32,
    ) -> Result<(), AgentError> {
        let code = format!("{passkey:06}");
        self.ask_yes_no("confirm", &device, json!({ "code": code }))
            .await
    }

    async fn request_authorization(&self, device: OwnedObjectPath) -> Result<(), AgentError> {
        self.ask_yes_no("authorize", &device, json!({})).await
    }

    async fn authorize_service(
        &self,
        device: OwnedObjectPath,
        uuid: String,
    ) -> Result<(), AgentError> {
        self.ask_yes_no("service", &device, json!({ "uuid": uuid }))
            .await
    }

    /// BlueZ withdrew its question: nobody answered within a minute, or the
    /// pairing ended some other way.
    fn cancel(&self) {
        self.cancel_all();
        emit(json!({"event": "cancel"}));
    }
}

#[proxy(
    interface = "org.bluez.AgentManager1",
    default_service = "org.bluez",
    default_path = "/org/bluez"
)]
trait AgentManager {
    fn register_agent(&self, agent: &ObjectPath<'_>, capability: &str) -> zbus::Result<()>;
    fn request_default_agent(&self, agent: &ObjectPath<'_>) -> zbus::Result<()>;
}

/// Tells BlueZ about the agent, and makes it the one BlueZ asks when the
/// program that started a pairing (here Quickshell) has no agent of its own.
async fn register(connection: &Connection) -> zbus::Result<()> {
    let manager = AgentManagerProxy::new(connection).await?;
    let path = ObjectPath::try_from(AGENT_PATH)?;
    match manager.register_agent(&path, CAPABILITY).await {
        // Still registered: BlueZ was not restarted after all.
        Err(zbus::Error::MethodError(name, _, _))
            if name.as_str() == "org.bluez.Error.AlreadyExists" => {}
        other => other?,
    }
    manager.request_default_agent(&path).await
}

/// A BlueZ that has only just started may not offer its agent manager yet,
/// so registering is tried for a few seconds.
async fn register_with_retries(connection: &Connection) {
    let mut last_error = None;
    for _ in 0..5 {
        match register(connection).await {
            Ok(()) => {
                emit(json!({"event": "ready"}));
                return;
            }
            Err(err) => last_error = Some(err),
        }
        async_io::Timer::after(Duration::from_secs(1)).await;
    }
    if let Some(err) = last_error {
        let message = format!("could not register with BlueZ: {err}");
        emit(json!({"event": "error", "message": message}));
    }
}

async fn run(waiting: Waiting) -> zbus::Result<()> {
    let agent = Agent {
        waiting,
        next_id: AtomicU64::new(1),
    };
    let connection = zbus::connection::Builder::system()?
        .serve_at(AGENT_PATH, agent)?
        .build()
        .await?;
    let bus = fdo::DBusProxy::new(&connection).await?;
    let mut changes = bus
        .receive_name_owner_changed_with_args(&[(0, "org.bluez")])
        .await?;
    let mut running = bus.name_has_owner("org.bluez".try_into()?).await?;
    loop {
        if running {
            register_with_retries(&connection).await;
        } else {
            emit(json!({"event": "waiting"}));
        }
        // Wait until BlueZ starts, stops or restarts. A restarted BlueZ has
        // forgotten every agent, so the loop registers again.
        let change = changes
            .next()
            .await
            .ok_or_else(|| zbus::Error::Failure("The system bus closed".into()))?;
        running = change.args()?.new_owner().is_some();
    }
}

fn main() {
    let waiting: Waiting = Arc::default();
    let answers = Arc::clone(&waiting);
    // The bar's answers arrive on stdin. A plain thread reads them and hands
    // each one to the question waiting for it.
    std::thread::spawn(move || {
        for line in std::io::stdin().lock().lines() {
            let Ok(line) = line else { break };
            if line.trim().is_empty() {
                continue;
            }
            match serde_json::from_str::<Answer>(&line) {
                // An answer that arrives after BlueZ withdrew its question has
                // nobody waiting for it, and is dropped.
                Ok(answer) => {
                    if let Some(sender) = answers.lock().unwrap().remove(&answer.id) {
                        let _ = sender.send(answer);
                    }
                }
                Err(err) => {
                    let message = format!("unreadable answer: {err}");
                    emit(json!({"event": "error", "message": message}));
                }
            }
        }
        // stdin closed: the bar quit or reloaded.
        std::process::exit(0);
    });
    if let Err(err) = async_io::block_on(run(waiting)) {
        emit(json!({"event": "error", "message": err.to_string()}));
        std::process::exit(1);
    }
}
