//! How a job talks to the bar: one JSON object per line, both ways. Lines to the
//! bar (stdout) carry an `"event"`; lines from the bar (stdin) are commands.
//!
//! The first line of every job is
//!
//! ```text
//! {"event":"hello","job":"bluetooth","version":"0.1.0"}
//! ```
//!
//! so the bar can tell a helper built from older sources (a `git pull` without a
//! reinstall) and say so. A problem that does not end the job is reported as
//! `{"event":"error","message":"..."}`; stderr is only for crashes. A job ends when
//! its stdin closes: the bar quit, reloaded, or no longer wants it.

use std::fmt::Display;
use std::io::{BufRead, Write};

use serde_json::{json, Value};

/// This program's version, from Cargo.toml.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Writes one line for the bar.
pub fn emit(line: Value) {
    let mut out = std::io::stdout().lock();
    // If the bar has gone, stdin has closed too and the job is about to end, so
    // a failed write needs nothing more.
    let _ = writeln!(out, "{line}");
    let _ = out.flush();
}

/// The first line of a job.
pub fn hello(job: &str) {
    emit(json!({"event": "hello", "job": job, "version": VERSION}));
}

/// A problem the job carries on after.
pub fn error(message: impl Display) {
    emit(json!({"event": "error", "message": message.to_string()}));
}

/// What a command is made of, for an error message: its keys, never what they
/// hold. A command can carry a copied text or a pairing code, and the bar
/// writes error messages to its log.
pub fn shape(command: &Value) -> String {
    match command {
        Value::Object(fields) => {
            let keys: Vec<&str> = fields.keys().map(String::as_str).collect();
            format!("{{{}}}", keys.join(", "))
        }
        Value::Null => "null".to_owned(),
        Value::Bool(_) => "a boolean".to_owned(),
        Value::Number(_) => "a number".to_owned(),
        Value::String(_) => "a string".to_owned(),
        Value::Array(_) => "a list".to_owned(),
    }
}

/// Hands each of the bar's commands to `on_command` until stdin closes, then
/// returns. Blank lines are skipped; a line that is not JSON is reported and
/// skipped.
pub fn read_commands(mut on_command: impl FnMut(Value)) {
    for line in std::io::stdin().lock().lines() {
        let Ok(line) = line else { break };
        if line.trim().is_empty() {
            continue;
        }
        match serde_json::from_str::<Value>(&line) {
            Ok(command) => on_command(command),
            Err(err) => error(format!("unreadable command: {err}")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_shape_of_a_command_names_its_keys_and_nothing_they_hold() {
        let command = json!({"copyText": "hunter2", "extra": ["hunter3"]});
        assert_eq!(shape(&command), "{copyText, extra}");
        assert_eq!(shape(&json!("hunter2")), "a string");
        assert_eq!(shape(&json!(["hunter2"])), "a list");
        assert_eq!(shape(&json!(1234)), "a number");
    }
}
