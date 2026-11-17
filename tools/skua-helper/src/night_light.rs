//! `skua-helper night-light`: warms the screens to a colour temperature.
//!
//! Wayland compositors such as niri and Hyprland let one program per screen set
//! that screen's gamma ramps (the wlr-gamma-control protocol). This job asks
//! for every screen's gamma control, screens plugged in later too, and sets
//! ramps computed as wlsunset did (gamma.rs).
//!
//! From the bar (stdin), one object per line:
//!
//! ```text
//! {"temperature":4000}   warm every screen to this many kelvin (1000 to 10000;
//!                        anything outside is moved to the nearest end). 6500 K
//!                        is normal white. Screens plugged in later get it too.
//! ```
//!
//! To the bar (stdout), after the hello line (protocol.rs):
//!
//! ```text
//! {"event":"state","temperature":4000,"outputs":[{"name":"DP-1","state":"applied"}]}
//!     once the screens are known, and again after every change. "temperature"
//!     is null until the first command; "name" is null until the compositor
//!     says it. A screen's state is
//!       "applied"   its ramps are set to the temperature
//!       "refused"   the compositor will not let this job set them: another
//!                   program holds that screen's gamma (another night light),
//!                   or the screen has none
//!       "waiting"   not set yet: no temperature yet, or the compositor has not
//!                   said yet how long that screen's ramps are
//! {"event":"error","message":"..."}   something failed; the job goes on
//! ```
//!
//! When a gamma control goes, the compositor puts that screen's own colours
//! back, so the bar ends night light by ending the job: stdin closes and the
//! job exits. A compositor without the protocol gets an error line and exit
//! code 3; losing the connection to the compositor ends the job with code 1.

use std::fs::File;
use std::io::{Seek, Write};
use std::os::fd::AsFd;
use std::process::ExitCode;

use calloop::channel::{self, Channel};
use calloop::EventLoop;
use calloop_wayland_source::WaylandSource;
use rustix::fs::{memfd_create, MemfdFlags};
use serde_json::{json, Value};
use wayland_client::globals::{registry_queue_init, GlobalListContents};
use wayland_client::protocol::wl_output::{self, WlOutput};
use wayland_client::protocol::wl_registry::{self, WlRegistry};
use wayland_client::{delegate_noop, Connection, Dispatch, Proxy, QueueHandle};
use wayland_protocols_wlr::gamma_control::v1::client::zwlr_gamma_control_manager_v1::ZwlrGammaControlManagerV1;
use wayland_protocols_wlr::gamma_control::v1::client::zwlr_gamma_control_v1::{
    self, ZwlrGammaControlV1,
};

use crate::gamma;
use crate::protocol::{self, emit};

/// The temperatures the bar may ask for, in kelvin.
const COLDEST: i32 = 10000;
const WARMEST: i32 = 1000;

/// Where a screen's ramps are; see the state line above.
#[derive(Clone, Copy, Debug, PartialEq)]
enum Status {
    Waiting,
    Applied,
    Refused,
}

impl Status {
    fn as_str(self) -> &'static str {
        match self {
            Status::Waiting => "waiting",
            Status::Applied => "applied",
            Status::Refused => "refused",
        }
    }
}

/// One screen: a wl_output and its gamma control.
struct Screen {
    /// The registry's number for this wl_output, by which its removal is told.
    global: u32,
    output: WlOutput,
    /// "DP-1", from wl_output version 4.
    name: Option<String>,
    /// None once the compositor has refused it.
    control: Option<ZwlrGammaControlV1>,
    /// Entries per ramp; 0 until the compositor says.
    size: u32,
    status: Status,
}

impl Screen {
    /// Sets this screen's ramps to `kelvin`, once the compositor has said how
    /// long they are. A refused screen is left alone.
    fn set(&mut self, kelvin: i32) {
        let Some(control) = &self.control else { return };
        if self.size == 0 {
            return;
        }
        let table = gamma::ramps(self.size, gamma::whitepoint(kelvin));
        match ramp_file(&table) {
            Ok(file) => {
                // The library duplicates the descriptor when it queues the
                // request, so this one can close straight after.
                control.set_gamma(file.as_fd());
                self.status = Status::Applied;
            }
            Err(err) => protocol::error(format!("could not hold the gamma table: {err}")),
        }
    }
}

/// The table in a file, which is how set_gamma wants it: a memfd (a file that
/// exists only in memory) holding the three ramps in this computer's byte order
/// and nothing else. A new one every time, read from its start: the compositor
/// reads it after this job has moved on, so it must never change.
fn ramp_file(table: &[u16]) -> std::io::Result<File> {
    let mut file = File::from(memfd_create("skua-gamma-ramps", MemfdFlags::CLOEXEC)?);
    let bytes: Vec<u8> = table.iter().flat_map(|value| value.to_ne_bytes()).collect();
    file.write_all(&bytes)?;
    file.rewind()?;
    Ok(file)
}

struct NightLight {
    manager: ZwlrGammaControlManagerV1,
    screens: Vec<Screen>,
    /// What the bar asked for last; None before its first command.
    temperature: Option<i32>,
    /// Something the state line shows has changed since it was last written.
    changed: bool,
}

impl NightLight {
    fn screen(&mut self, global: u32) -> Option<&mut Screen> {
        self.screens
            .iter_mut()
            .find(|screen| screen.global == global)
    }

    fn add_screen(
        &mut self,
        registry: &WlRegistry,
        global: u32,
        version: u32,
        qh: &QueueHandle<Self>,
    ) {
        // Version 4 is the first to tell the screen's name.
        let output: WlOutput = registry.bind(global, version.min(4), qh, global);
        let control = self.manager.get_gamma_control(&output, qh, global);
        self.screens.push(Screen {
            global,
            output,
            name: None,
            control: Some(control),
            size: 0,
            status: Status::Waiting,
        });
        // No line yet: the compositor answers at once with the screen's name
        // and ramp size (or a refusal), and that answer gives the line, so a
        // new screen shows up named and set rather than as a nameless
        // "waiting" first.
    }

    fn remove_screen(&mut self, global: u32) {
        let Some(index) = self
            .screens
            .iter()
            .position(|screen| screen.global == global)
        else {
            return;
        };
        let screen = self.screens.remove(index);
        if let Some(control) = screen.control {
            control.destroy();
        }
        if screen.output.version() >= 3 {
            screen.output.release();
        }
        self.changed = true;
    }

    fn set_temperature(&mut self, kelvin: i32) {
        self.temperature = Some(kelvin);
        for screen in &mut self.screens {
            screen.set(kelvin);
        }
        self.changed = true;
    }

    /// Writes the state line if anything in it has changed. Runs after each
    /// round of events, so a burst of them (a new screen's name, then its
    /// ramp size) gives one line.
    fn report(&mut self) {
        if !self.changed {
            return;
        }
        self.changed = false;
        emit(state_line(
            self.temperature,
            self.screens
                .iter()
                .map(|screen| (screen.name.as_deref(), screen.status)),
        ));
    }
}

fn state_line<'a>(
    temperature: Option<i32>,
    screens: impl Iterator<Item = (Option<&'a str>, Status)>,
) -> Value {
    let outputs: Vec<Value> = screens
        .map(|(name, status)| json!({"name": name, "state": status.as_str()}))
        .collect();
    json!({"event": "state", "temperature": temperature, "outputs": outputs})
}

/// The temperature a command asks for, moved into the range this job takes.
/// None when it is not a temperature command.
fn temperature_of(command: &Value) -> Option<i32> {
    let kelvin = command.get("temperature")?.as_f64()?;
    // `as` turns a value far outside i32 into its nearest end, which the
    // clamp then moves into range.
    Some((kelvin.round() as i32).clamp(WARMEST, COLDEST))
}

impl Dispatch<WlRegistry, GlobalListContents> for NightLight {
    fn event(
        state: &mut Self,
        registry: &WlRegistry,
        event: wl_registry::Event,
        _: &GlobalListContents,
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        match event {
            wl_registry::Event::Global {
                name,
                interface,
                version,
            } if interface == WlOutput::interface().name => {
                state.add_screen(registry, name, version, qh);
            }
            wl_registry::Event::GlobalRemove { name } => state.remove_screen(name),
            _ => {}
        }
    }
}

impl Dispatch<WlOutput, u32> for NightLight {
    fn event(
        state: &mut Self,
        _: &WlOutput,
        event: wl_output::Event,
        global: &u32,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        // The name comes once, in answer to the bind, so always before the
        // answer to the gamma control asked for after it; that answer writes
        // the line, with the name in it.
        if let wl_output::Event::Name { name } = event {
            if let Some(screen) = state.screen(*global) {
                screen.name = Some(name);
            }
        }
    }
}

impl Dispatch<ZwlrGammaControlV1, u32> for NightLight {
    fn event(
        state: &mut Self,
        control: &ZwlrGammaControlV1,
        event: zwlr_gamma_control_v1::Event,
        global: &u32,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        let temperature = state.temperature;
        let Some(screen) = state.screen(*global) else {
            return;
        };
        match event {
            zwlr_gamma_control_v1::Event::GammaSize { size } if size > 0 => {
                screen.size = size;
                if let Some(kelvin) = temperature {
                    screen.set(kelvin);
                }
            }
            // Refused: another program holds this screen's gamma, the screen
            // has none, or setting it failed. A size of 0 leaves no ramp to
            // set, which comes to the same. The protocol wants it destroyed.
            zwlr_gamma_control_v1::Event::GammaSize { .. }
            | zwlr_gamma_control_v1::Event::Failed => {
                control.destroy();
                screen.control = None;
                screen.status = Status::Refused;
            }
            _ => return,
        }
        state.changed = true;
    }
}

delegate_noop!(NightLight: ZwlrGammaControlManagerV1);

pub fn run() -> ExitCode {
    protocol::hello("night-light");
    let connection = match Connection::connect_to_env() {
        Ok(connection) => connection,
        Err(err) => {
            protocol::error(format!("could not connect to the compositor: {err}"));
            return ExitCode::FAILURE;
        }
    };
    let (globals, mut queue) = match registry_queue_init::<NightLight>(&connection) {
        Ok(found) => found,
        Err(err) => {
            protocol::error(format!("could not list what the compositor offers: {err}"));
            return ExitCode::FAILURE;
        }
    };
    let qh = queue.handle();
    let Ok(manager) = globals.bind::<ZwlrGammaControlManagerV1, _, _>(&qh, 1..=1, ()) else {
        protocol::error("the compositor offers no gamma control (wlr-gamma-control), so night light cannot work");
        return ExitCode::from(3);
    };
    let mut state = NightLight {
        manager,
        screens: Vec::new(),
        temperature: None,
        changed: true,
    };
    for global in globals.contents().clone_list() {
        if global.interface == WlOutput::interface().name {
            state.add_screen(globals.registry(), global.name, global.version, &qh);
        }
    }
    // The replies carry every screen's name and ramp size, or its refusal.
    if let Err(err) = queue.roundtrip(&mut state) {
        protocol::error(format!("lost the connection to the compositor: {err}"));
        return ExitCode::FAILURE;
    }
    state.report();

    match run_loop(connection, queue, state) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            protocol::error(format!("lost the connection to the compositor: {err}"));
            ExitCode::FAILURE
        }
    }
}

/// Waits for the compositor's events and the bar's commands until stdin
/// closes (Ok) or the compositor goes (Err).
fn run_loop(
    connection: Connection,
    queue: wayland_client::EventQueue<NightLight>,
    mut state: NightLight,
) -> Result<(), calloop::Error> {
    let mut event_loop: EventLoop<NightLight> = EventLoop::try_new()?;
    WaylandSource::new(connection, queue)
        .insert(event_loop.handle())
        .map_err(|err| err.error)?;

    // A plain thread reads stdin and hands each command to the loop. When
    // stdin closes the thread ends, its sender goes, and the channel says so.
    let (sender, commands): (_, Channel<Value>) = channel::channel();
    std::thread::spawn(move || {
        protocol::read_commands(|command| {
            let _ = sender.send(command);
        });
    });
    let stop = event_loop.get_signal();
    event_loop
        .handle()
        .insert_source(
            commands,
            move |event, _, state: &mut NightLight| match event {
                channel::Event::Msg(command) => match temperature_of(&command) {
                    Some(kelvin) => state.set_temperature(kelvin),
                    None => protocol::error(format!("unknown command: {command}")),
                },
                channel::Event::Closed => stop.stop(),
            },
        )
        .map_err(|err| err.error)?;

    event_loop.run(None, &mut state, NightLight::report)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn temperatures_are_read_and_kept_in_range() {
        assert_eq!(temperature_of(&json!({"temperature": 4000})), Some(4000));
        assert_eq!(temperature_of(&json!({"temperature": 6500})), Some(6500));
        assert_eq!(temperature_of(&json!({"temperature": 3999.6})), Some(4000));
        assert_eq!(temperature_of(&json!({"temperature": 1000})), Some(1000));
        assert_eq!(temperature_of(&json!({"temperature": 999})), Some(1000));
        assert_eq!(temperature_of(&json!({"temperature": -5})), Some(1000));
        assert_eq!(temperature_of(&json!({"temperature": 10001})), Some(10000));
        assert_eq!(temperature_of(&json!({"temperature": 1e300})), Some(10000));
    }

    #[test]
    fn other_commands_are_not_temperatures() {
        assert_eq!(temperature_of(&json!({"temperature": "4000"})), None);
        assert_eq!(temperature_of(&json!({"temperature": null})), None);
        assert_eq!(temperature_of(&json!({"kelvin": 4000})), None);
        assert_eq!(temperature_of(&json!([4000])), None);
        assert_eq!(temperature_of(&json!(4000)), None);
    }

    #[test]
    fn the_state_line_lists_every_screen() {
        let screens = [
            (Some("DP-1"), Status::Applied),
            (Some("HDMI-A-1"), Status::Refused),
            (None, Status::Waiting),
        ];
        assert_eq!(
            state_line(Some(4000), screens.into_iter()),
            json!({
                "event": "state",
                "temperature": 4000,
                "outputs": [
                    {"name": "DP-1", "state": "applied"},
                    {"name": "HDMI-A-1", "state": "refused"},
                    {"name": null, "state": "waiting"},
                ],
            })
        );
        assert_eq!(
            state_line(None, std::iter::empty()),
            json!({"event": "state", "temperature": null, "outputs": []})
        );
    }
}
