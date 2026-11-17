//! skua-helper: the background jobs Skua (a Quickshell bar) cannot do in QML.
//!
//! ```text
//! skua-helper bluetooth     answer BlueZ's pairing questions (bluetooth.rs)
//! skua-helper --version
//! ```
//!
//! The bar starts each job as its own process, so one job failing never stops
//! another, and talks to it one line of JSON at a time (protocol.rs).

mod bluetooth;
mod protocol;

use std::process::ExitCode;

const USAGE: &str = "usage: skua-helper <job>

jobs:
  bluetooth    answer BlueZ's pairing questions for Skua

  --version    print the version
";

fn main() -> ExitCode {
    match std::env::args().nth(1).as_deref() {
        Some("bluetooth") => bluetooth::run(),
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
