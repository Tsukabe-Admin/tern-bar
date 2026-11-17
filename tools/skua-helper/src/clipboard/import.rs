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

use std::ffi::{OsStr, OsString};
use std::io;
use std::os::unix::ffi::OsStrExt;
use std::process::{Command, Stdio};

use super::content::{self, Kind, TEXT_TYPES};

/// One entry read from cliphist.
#[derive(Debug, PartialEq)]
pub struct Old {
    pub kind: Kind,
    pub mime: &'static str,
    pub data: Vec<u8>,
}

pub struct Cliphist {
    /// "cliphist"; another name only in a test.
    program: &'static str,
    /// Flags given to every cliphist command.
    flags: Vec<OsString>,
}

impl Cliphist {
    pub fn from_env() -> Cliphist {
        let flags = match std::env::var_os("SKUA_CLIPHIST_DB") {
            Some(path) => vec!["-db-path".into(), path],
            None => Vec::new(),
        };
        Cliphist {
            program: "cliphist",
            flags,
        }
    }

    fn command(&self, what: &str) -> Command {
        let mut command = Command::new(self.program);
        command.args(&self.flags).arg(what).stdin(Stdio::null());
        command
    }

    /// Hands the newest `max` entries to `each`, newest first, until `each`
    /// returns false. An entry cliphist cannot decode, one over the size
    /// limit or one that is neither an image nor text is left out. Without
    /// cliphist installed there is nothing to import, which is no error.
    pub fn read(&self, max: usize, mut each: impl FnMut(Old) -> bool) -> Result<(), String> {
        let listed = match self.command("list").output() {
            Ok(output) => output,
            Err(err) if err.kind() == io::ErrorKind::NotFound => return Ok(()),
            Err(err) => return Err(format!("cannot run cliphist: {err}")),
        };
        if !listed.status.success() {
            return Err(format!(
                "cliphist list failed: {}",
                String::from_utf8_lossy(&listed.stderr).trim()
            ));
        }
        // Each line is "ID<tab>preview".
        let ids = listed
            .stdout
            .split(|byte| *byte == b'\n')
            .filter_map(|line| line.split(|byte| *byte == b'\t').next())
            .filter(|id| !id.is_empty() && id.iter().all(u8::is_ascii_digit))
            .take(max);
        for id in ids {
            let decoded = self
                .command("decode")
                .arg(OsStr::from_bytes(id))
                .stderr(Stdio::null())
                .output()
                .map_err(|err| format!("cannot run cliphist: {err}"))?;
            if !decoded.status.success() {
                continue;
            }
            if let Some(old) = recognise(decoded.stdout) {
                if !each(old) {
                    break;
                }
            }
        }
        Ok(())
    }
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
            program: "cliphist",
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
            program: "cliphist-that-is-not-installed",
            flags: Vec::new(),
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
