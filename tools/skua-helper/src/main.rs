//! skua-helper: the background jobs Skua (a Quickshell bar) cannot do in QML.
//!
//! ```text
//! skua-helper bluetooth     answer BlueZ's pairing questions (bluetooth.rs)
//! skua-helper night-light   warm the screens' colours (night_light.rs, gamma.rs)
//! skua-helper --version
//! ```
//!
//! The bar starts each job as its own process, so one job failing never stops
//! another, and talks to it one line of JSON at a time (protocol.rs).

mod bluetooth;
mod gamma;
mod night_light;
mod protocol;

use std::process::ExitCode;

const USAGE: &str = "usage: skua-helper <job>

jobs:
  bluetooth    answer BlueZ's pairing questions for Skua
  night-light  warm the screens' colours to a temperature Skua sends

  --version    print the version
";

fn main() -> ExitCode {
    match std::env::args().nth(1).as_deref() {
        Some("bluetooth") => bluetooth::run(),
        Some("night-light") => night_light::run(),
        Some("--version" | "-V") => {
            println!("skua-helper {}", protocol::VERSION);
            ExitCode::SUCCESS
        }
        _ => {
            eprint!("{USAGE}");
            ExitCode::from(2)
        }
    }
}
