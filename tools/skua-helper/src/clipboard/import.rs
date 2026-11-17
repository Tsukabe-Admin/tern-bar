//! A one-time import of an existing cliphist history, so switching to this job
//! does not lose what was copied before. cliphist itself does the reading:
//! `cliphist list` gives the entries newest first, and `cliphist decode ID`
//! gives each one's bytes. cliphist does not record what type an entry was,
//! so an image is recognised by its first bytes (PNG, JPEG, WebP, GIF) and
//! anything else that is UTF-8 is text.
//!
//! cliphist uses its own database (`~/.cache/cliphist/db`) unless
//! `SKUA_CLIPHIST_DB` names another one, which is passed on as its
//! `-db-path`.
//!
//! A database is only a file, and what is in it decides what cliphist prints,
//! so nothing cliphist prints is trusted to be small or to end: each command's
//! output is read up to a limit and for a limited time, and then the command
//! is stopped.

use std::ffi::{OsStr, OsString};
use std::io::{self, Read};
use std::os::unix::ffi::OsStrExt;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use super::content::{self, Kind, TEXT_TYPES};

/// The longest one cliphist command may take. Listing, or decoding one entry,
/// takes milliseconds.
const PATIENCE: Duration = Duration::from_secs(10);

/// The most of `cliphist list` that is read: far more than the lines of the
/// newest 500 entries, which come first.
const LIST_LIMIT: usize = 4 << 20;

const TOO_SLOW: &str = "cliphist took too long to answer";

/// One entry read from cliphist.
#[derive(Debug, PartialEq)]
pub struct Old {
    pub kind: Kind,
    pub mime: &'static str,
    pub data: Vec<u8>,
}

pub struct Cliphist {
    /// "cliphist"; another program only in a test.
    program: OsString,
    /// Flags given to every cliphist command.
    flags: Vec<OsString>,
    /// PATIENCE; less only in a test.
    patience: Duration,
}

impl Cliphist {
    pub fn from_env() -> Cliphist {
        let flags = match std::env::var_os("SKUA_CLIPHIST_DB") {
            Some(path) => vec!["-db-path".into(), path],
            None => Vec::new(),
        };
        Cliphist {
            program: "cliphist".into(),
            flags,
            patience: PATIENCE,
        }
    }

    fn command(&self, what: &str) -> Command {
        let mut command = Command::new(&self.program);
        command.args(&self.flags).arg(what).stdin(Stdio::null());
        command
    }

    /// Hands the newest `max` entries to `each`, newest first, until `each`
    /// returns false. An entry cliphist cannot decode, one over the size
    /// limit or one that is neither an image nor text is left out. Without
    /// cliphist installed there is nothing to import, which is no error. A
    /// cliphist that does not answer in time is one: the import ends there.
    pub fn read(&self, max: usize, mut each: impl FnMut(Old) -> bool) -> Result<(), String> {
        let (mut listed, end) = match run(self.command("list"), LIST_LIMIT, self.patience) {
            Ok(ran) => ran,
            Err(err) if err.kind() == io::ErrorKind::NotFound => return Ok(()),
            Err(err) => return Err(format!("cannot run cliphist: {err}")),
        };
        match end {
            End::Exited(true) => {}
            End::Exited(false) => return Err("cliphist list failed".to_owned()),
            // The start of a very long list is all that is needed, without
            // the line that was cut.
            End::TooMuch => {
                let whole = listed.iter().rposition(|byte| *byte == b'\n');
                listed.truncate(whole.map_or(0, |at| at + 1));
            }
            End::TimedOut => return Err(TOO_SLOW.to_owned()),
        }
        // Each line is "ID<tab>preview".
        let ids = listed
            .split(|byte| *byte == b'\n')
            .filter_map(|line| line.split(|byte| *byte == b'\t').next())
            .filter(|id| !id.is_empty() && id.iter().all(u8::is_ascii_digit))
            .take(max);
        for id in ids {
            let mut decode = self.command("decode");
            decode.arg(OsStr::from_bytes(id));
            let (data, end) = run(decode, Kind::Image.limit(), self.patience)
                .map_err(|err| format!("cannot run cliphist: {err}"))?;
            match end {
                End::Exited(true) => {}
                // Not decodable, or larger than anything that is kept.
                End::Exited(false) | End::TooMuch => continue,
                End::TimedOut => return Err(TOO_SLOW.to_owned()),
            }
            if let Some(old) = recognise(data) {
                if !each(old) {
                    break;
                }
            }
        }
        Ok(())
    }
}

/// How a command ended.
enum End {
    /// By itself; true when it reported success.
    Exited(bool),
    /// Stopped: it printed more than the limit.
    TooMuch,
    /// Stopped: its time was up.
    TimedOut,
}

/// Runs a command and returns what it printed, `limit` bytes at most, and
/// how it ended. It is never waited for longer than `patience`.
fn run(mut command: Command, limit: usize, patience: Duration) -> io::Result<(Vec<u8>, End)> {
    let until = Instant::now() + patience;
    let mut child = command
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()?;
    let stdout = child.stdout.take();
    // Read in a thread of its own, so that the wait for it can end.
    let (sender, received) = mpsc::channel();
    std::thread::spawn(move || {
        let mut output = Vec::new();
        if let Some(stdout) = stdout {
            let _ = stdout.take(limit as u64 + 1).read_to_end(&mut output);
        }
        let _ = sender.send(output);
    });
    let (output, end) = match received.recv_timeout(patience) {
        Ok(mut output) if output.len() > limit => {
            output.truncate(limit);
            (output, End::TooMuch)
        }
        // It closed its output, so it is about to end.
        Ok(output) => loop {
            match child.try_wait() {
                Ok(Some(status)) => break (output, End::Exited(status.success())),
                Ok(None) if Instant::now() < until => {
                    std::thread::sleep(Duration::from_millis(1));
                }
                _ => break (output, End::TimedOut),
            }
        },
        Err(_) => (Vec::new(), End::TimedOut),
    };
    if !matches!(end, End::Exited(_)) {
        let _ = child.kill();
        let _ = child.wait();
    }
    Ok((output, end))
}

/// What an imported entry is: an image by its first bytes, text if it is
/// UTF-8, otherwise nothing kept.
pub fn recognise(data: Vec<u8>) -> Option<Old> {
    let (kind, mime) = match content::sniff_image(&data) {
        Some(mime) => (Kind::Image, mime),
        None if std::str::from_utf8(&data).is_ok() => (Kind::Text, TEXT_TYPES[0]),
        None => return None,
    };
    if data.is_empty() || data.len() > kind.limit() {
        return None;
    }
    Some(Old { kind, mime, data })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::clipboard::content::tests::PNG;
    use crate::clipboard::store::Store;
    use std::io::Write;
    use std::path::Path;

    /// The import tests need a real cliphist; without one they are skipped.
    fn have_cliphist() -> bool {
        let found = Command::new("cliphist").arg("version").output().is_ok();
        if !found {
            eprintln!("cliphist is not installed: skipped");
        }
        found
    }

    /// A scratch cliphist that never reads the user's own settings or history.
    fn scratch(dir: &Path) -> Cliphist {
        Cliphist {
            program: "cliphist".into(),
            flags: vec![
                "-db-path".into(),
                dir.join("db").into(),
                "-config-path".into(),
                dir.join("no-config").into(),
                // Keep a second copy of the same text, as an old cliphist
                // history can have.
                "-max-dedupe-search".into(),
                "0".into(),
            ],
            patience: PATIENCE,
        }
    }

    fn store(cliphist: &Cliphist, data: &[u8]) {
        let mut child = cliphist
            .command("store")
            .stdin(Stdio::piped())
            .env_remove("CLIPBOARD_STATE")
            .spawn()
            .expect("cliphist is installed");
        child.stdin.take().unwrap().write_all(data).unwrap();
        assert!(child.wait().unwrap().success());
    }

    /// A stand-in cliphist, for what a real one never does on its own: a
    /// shell script whose `list` and `decode ID` do what the test says.
    fn fake(dir: &Path, list: &str, decode: &str, patience: Duration) -> Cliphist {
        let script = dir.join("fake-cliphist.sh");
        let text = format!(
            "case \"$1\" in\nlist) {list} ;;\ndecode) case \"$2\" in\n{decode}\nesac ;;\nesac\n"
        );
        std::fs::write(&script, text).unwrap();
        Cliphist {
            program: "sh".into(),
            flags: vec![script.into()],
            patience,
        }
    }

    const THREE: &str = r"printf '3\tthree\n2\ttwo\n1\tone\n'";

    fn texts(cliphist: &Cliphist, max: usize) -> (Result<(), String>, Vec<String>) {
        let mut read = Vec::new();
        let done = cliphist.read(max, |old| {
            read.push(String::from_utf8(old.data).unwrap());
            true
        });
        (done, read)
    }

    #[test]
    fn an_entry_that_never_ends_is_cut_off_and_left_out() {
        let dir = tempfile::tempdir().unwrap();
        // Entry 2 prints without end; one of many gigabytes looks the same.
        let decode = "3) printf three ;;\n2) exec yes ;;\n1) printf one ;;";
        let cliphist = fake(dir.path(), THREE, decode, Duration::from_secs(20));
        let started = Instant::now();
        let (done, read) = texts(&cliphist, 500);
        assert_eq!(done, Ok(()));
        assert_eq!(read, ["three", "one"]);
        assert!(started.elapsed() < Duration::from_secs(15));
    }

    #[test]
    fn a_list_that_never_ends_still_gives_its_first_entries() {
        let dir = tempfile::tempdir().unwrap();
        let list = r#"exec yes "$(printf '7\tspam')""#;
        let cliphist = fake(
            dir.path(),
            list,
            "7) printf seven ;;",
            Duration::from_secs(20),
        );
        let (done, read) = texts(&cliphist, 2);
        assert_eq!(done, Ok(()));
        assert_eq!(read, ["seven", "seven"]);
    }

    #[test]
    fn a_cliphist_that_hangs_ends_the_import_with_an_error() {
        let dir = tempfile::tempdir().unwrap();
        let decode = "3) printf three ;;\n2) exec sleep 60 ;;\n1) printf one ;;";
        let cliphist = fake(dir.path(), THREE, decode, Duration::from_millis(400));
        let started = Instant::now();
        let (done, read) = texts(&cliphist, 500);
        assert_eq!(done, Err(TOO_SLOW.to_owned()));
        assert_eq!(read, ["three"]);
        assert!(started.elapsed() < Duration::from_secs(10));
    }

    #[test]
    fn recognises_kinds() {
        assert_eq!(recognise(PNG.to_vec()).unwrap().mime, "image/png");
        let text = recognise(b"hello".to_vec()).unwrap();
        assert_eq!(
            (text.kind, text.mime),
            (Kind::Text, "text/plain;charset=utf-8")
        );
        assert!(recognise(b"\x00\xff\xfe binary".to_vec()).is_none());
        assert!(recognise(Vec::new()).is_none());
        assert!(recognise(vec![b'a'; Kind::Text.limit() + 1]).is_none());
        assert!(recognise(vec![b'a'; Kind::Text.limit()]).is_some());
    }

    #[test]
    fn a_missing_cliphist_has_nothing_to_import() {
        let cliphist = Cliphist {
            program: "cliphist-that-is-not-installed".into(),
            flags: Vec::new(),
            patience: PATIENCE,
        };
        let mut read = 0;
        let done = cliphist.read(500, |_| {
            read += 1;
            true
        });
        assert_eq!((done, read), (Ok(()), 0));
    }

    #[test]
    fn imports_a_cliphist_history() {
        if !have_cliphist() {
            return;
        }
        let dir = tempfile::tempdir().unwrap();
        let cliphist = scratch(dir.path());
        // Oldest first, as they were copied.
        store(&cliphist, b"first text");
        store(&cliphist, &PNG);
        store(&cliphist, b"second text\nwith two lines");
        store(&cliphist, b"first text");
        store(&cliphist, b"newest");

        let mut read = Vec::new();
        cliphist
            .read(500, |old| {
                read.push(old);
                true
            })
            .unwrap();
        let kinds: Vec<_> = read.iter().map(|old| (old.kind, old.data.len())).collect();
        assert_eq!(
            kinds,
            [
                (Kind::Text, 6),
                (Kind::Text, 10),
                (Kind::Text, 26),
                (Kind::Image, PNG.len()),
                (Kind::Text, 10),
            ],
            "newest first, the repeated text twice"
        );

        // Into a store that already holds one of them.
        let mut history = Store::open(dir.path().join("history")).unwrap();
        history
            .add(Kind::Text, "UTF8_STRING", b"newest", 100)
            .unwrap();
        let added: Vec<_> = read
            .into_iter()
            .filter_map(|old| history.add_old(old.kind, old.mime, &old.data).unwrap())
            .collect();
        assert_eq!(added.len(), 3, "newest and the repeat are skipped");
        let previews: Vec<_> = history.items().map(|item| item.preview.as_str()).collect();
        assert_eq!(
            previews,
            [
                "newest",
                "first text",
                "second text with two lines",
                "PNG 3×2"
            ]
        );
        let image = history.items().nth(3).unwrap();
        assert_eq!(
            (image.kind, image.mime.as_str()),
            (Kind::Image, "image/png")
        );
        assert_eq!(history.read(image.id).unwrap(), PNG);
    }

    #[test]
    fn takes_only_the_newest() {
        if !have_cliphist() {
            return;
        }
        let dir = tempfile::tempdir().unwrap();
        let cliphist = scratch(dir.path());
        for n in 0..5 {
            store(&cliphist, format!("entry {n}").as_bytes());
        }
        let mut read = Vec::new();
        cliphist
            .read(2, |old| {
                read.push(String::from_utf8(old.data).unwrap());
                true
            })
            .unwrap();
        assert_eq!(read, ["entry 4", "entry 3"]);
    }
}
