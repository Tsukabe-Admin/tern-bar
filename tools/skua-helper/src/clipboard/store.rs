//! The clipboard history on disk, in `$XDG_STATE_HOME/skua/clipboard`
//! (`~/.local/state/skua/clipboard` when that is not set):
//!
//! ```text
//! index.json    the entries, newest first, and the job's own settings
//! 17.txt        one file per entry, named by its id: the copied bytes as they were
//! 18.png
//! ```
//!
//! Only this user may open the folder (0700) or its files (0600): copied text
//! can be private. Files are written under a temporary name and renamed into
//! place, so a crash leaves the old file or the new one, never half of one.
//! Opening the store drops an entry whose file is missing or the wrong size,
//! and deletes a file no entry names (one written just before a crash).
//!
//! Ids are numbers that are never reused, so the bar can go on using one it
//! was given, also across restarts.

use std::fs::{self, DirBuilder, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use super::content::{self, Kind};

/// The most entries kept. A new one beyond this deletes the oldest.
pub const MAX_ITEMS: usize = 500;

const INDEX: &str = "index.json";

/// One entry as the bar sees it.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Item {
    pub id: u64,
    pub kind: Kind,
    /// The type it was copied as; a text entry is offered under every
    /// plain-text name when copied back.
    pub mime: String,
    /// One line to show and search (content.rs).
    pub preview: String,
    /// When it was copied, or last copied again, in seconds since 1970. 0 for
    /// an entry imported from cliphist, which does not record it.
    pub time: u64,
    /// Bytes.
    pub size: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub width: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub height: Option<u32>,
}

#[derive(Clone, Serialize, Deserialize)]
struct Entry {
    #[serde(flatten)]
    item: Item,
    /// content::hash of the bytes: finds a duplicate without reading every file.
    hash: u64,
}

#[derive(Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
struct Index {
    next_id: u64,
    paused: bool,
    /// A cliphist history was imported into this one (or there was none).
    imported: bool,
    /// Newest first.
    entries: Vec<Entry>,
}

impl Default for Index {
    fn default() -> Index {
        Index {
            next_id: 1,
            paused: false,
            imported: false,
            entries: Vec::new(),
        }
    }
}

/// What adding an entry changed.
#[derive(Debug)]
pub struct Added {
    /// The entry now at the top: a new one, or an older copy of the same
    /// content moved up.
    pub item: Item,
    /// Old entries deleted to stay within MAX_ITEMS.
    pub dropped: Vec<u64>,
}

pub struct Store {
    dir: PathBuf,
    index: Index,
}

/// `$XDG_STATE_HOME/skua/clipboard`, or `~/.local/state/skua/clipboard`.
pub fn default_dir() -> Option<PathBuf> {
    let state = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
        .or_else(|| {
            let home = PathBuf::from(std::env::var_os("HOME")?);
            Some(home.join(".local/state"))
        })?;
    Some(state.join("skua/clipboard"))
}

impl Store {
    /// Opens the history in `dir`, creating it if needed.
    pub fn open(dir: PathBuf) -> io::Result<Store> {
        if let Some(parent) = dir.parent() {
            fs::create_dir_all(parent)?;
        }
        match DirBuilder::new().mode(0o700).create(&dir) {
            Err(err) if err.kind() != io::ErrorKind::AlreadyExists => return Err(err),
            _ => {}
        }
        // A folder made by something else may be open to others.
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o700))?;

        let path = dir.join(INDEX);
        let mut index: Index = match fs::read(&path) {
            // The serde message is left out: it can quote what it found, and
            // that is a piece of the history. The bar logs this.
            Ok(text) => serde_json::from_slice(&text).map_err(|err| {
                io::Error::other(format!(
                    "{} cannot be read ({} at line {}, column {}); move it away to start a new history",
                    path.display(),
                    match err.classify() {
                        serde_json::error::Category::Data => "not a history index",
                        _ => "not JSON",
                    },
                    err.line(),
                    err.column()
                ))
            })?,
            Err(err) if err.kind() == io::ErrorKind::NotFound => Index::default(),
            Err(err) => return Err(err),
        };

        let mut store = Store {
            dir,
            index: Index::default(),
        };
        let before = index.entries.len();
        index.entries.retain(|entry| {
            fs::metadata(store.path_of(&entry.item)).is_ok_and(|meta| meta.len() == entry.item.size)
        });
        let changed = index.entries.len() != before;
        let highest = index.entries.iter().map(|entry| entry.item.id).max();
        index.next_id = index.next_id.max(highest.map_or(1, |id| id + 1));
        store.index = index;
        if changed {
            store.save()?;
        }
        store.delete_strays()?;
        Ok(store)
    }

    /// Deletes files that no entry names: an entry file or an index written
    /// just before a crash. Only names this store gives are touched.
    fn delete_strays(&self) -> io::Result<()> {
        let named: Vec<PathBuf> = self
            .index
            .entries
            .iter()
            .map(|entry| self.path_of(&entry.item))
            .collect();
        for found in fs::read_dir(&self.dir)? {
            let path = found?.path();
            let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
                continue;
            };
            let ours = name.starts_with(|c: char| c.is_ascii_digit()) || name.ends_with(".tmp");
            if ours && !named.contains(&path) {
                remove_file(&path)?;
            }
        }
        Ok(())
    }

    /// The entries, newest first.
    pub fn items(&self) -> impl Iterator<Item = &Item> {
        self.index.entries.iter().map(|entry| &entry.item)
    }

    pub fn item(&self, id: u64) -> Option<&Item> {
        self.items().find(|item| item.id == id)
    }

    pub fn len(&self) -> usize {
        self.index.entries.len()
    }

    pub fn paused(&self) -> bool {
        self.index.paused
    }

    pub fn set_paused(&mut self, paused: bool) -> io::Result<()> {
        self.index.paused = paused;
        self.save()
    }

    pub fn imported(&self) -> bool {
        self.index.imported
    }

    pub fn set_imported(&mut self) -> io::Result<()> {
        self.index.imported = true;
        self.save()
    }

    /// An entry's bytes.
    pub fn read(&self, id: u64) -> io::Result<Vec<u8>> {
        let item = self
            .item(id)
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no such entry"))?;
        fs::read(self.path_of(item))
    }

    /// Puts new content at the top. Content already in the history is not
    /// stored twice: its entry moves to the top instead, keeping its id.
    pub fn add(&mut self, kind: Kind, mime: &str, data: &[u8], time: u64) -> io::Result<Added> {
        let hash = content::hash(data);
        if let Some(at) = self.find(kind, data, hash)? {
            let mut entry = self.index.entries.remove(at);
            entry.item.time = time;
            let item = entry.item.clone();
            self.index.entries.insert(0, entry);
            self.save()?;
            return Ok(Added {
                item,
                dropped: Vec::new(),
            });
        }
        let entry = self.write_entry(kind, mime, data, hash, time)?;
        let item = entry.item.clone();
        self.index.entries.insert(0, entry);
        let old = if self.index.entries.len() > MAX_ITEMS {
            self.index.entries.split_off(MAX_ITEMS)
        } else {
            Vec::new()
        };
        self.save()?;
        let mut dropped = Vec::with_capacity(old.len());
        for entry in old {
            remove_file(&self.path_of(&entry.item))?;
            dropped.push(entry.item.id);
        }
        Ok(Added { item, dropped })
    }

    /// Puts older content at the bottom, for an import: None when it is
    /// already in the history or the history is full. The index is written
    /// by save() once the import is done.
    pub fn add_old(&mut self, kind: Kind, mime: &str, data: &[u8]) -> io::Result<Option<Item>> {
        if self.index.entries.len() >= MAX_ITEMS {
            return Ok(None);
        }
        let hash = content::hash(data);
        if self.find(kind, data, hash)?.is_some() {
            return Ok(None);
        }
        let entry = self.write_entry(kind, mime, data, hash, 0)?;
        let item = entry.item.clone();
        self.index.entries.push(entry);
        Ok(Some(item))
    }

    /// Moves an entry to the top, as copying it does.
    pub fn touch(&mut self, id: u64, time: u64) -> io::Result<Option<Item>> {
        let Some(at) = self.position(id) else {
            return Ok(None);
        };
        let mut entry = self.index.entries.remove(at);
        entry.item.time = time;
        let item = entry.item.clone();
        self.index.entries.insert(0, entry);
        self.save()?;
        Ok(Some(item))
    }

    /// False when there is no such entry.
    pub fn remove(&mut self, id: u64) -> io::Result<bool> {
        let Some(at) = self.position(id) else {
            return Ok(false);
        };
        let entry = self.index.entries.remove(at);
        self.save()?;
        remove_file(&self.path_of(&entry.item))?;
        Ok(true)
    }

    pub fn clear(&mut self) -> io::Result<()> {
        let entries = std::mem::take(&mut self.index.entries);
        self.save()?;
        for entry in &entries {
            remove_file(&self.path_of(&entry.item))?;
        }
        Ok(())
    }

    /// Writes the index.
    pub fn save(&self) -> io::Result<()> {
        let text = serde_json::to_vec(&self.index).map_err(io::Error::other)?;
        // The index is small and says which files count, so it is on disk
        // before it replaces the old one: a crash cannot leave an empty one.
        write_file(&self.dir.join(INDEX), &text, true)
    }

    fn position(&self, id: u64) -> Option<usize> {
        self.index
            .entries
            .iter()
            .position(|entry| entry.item.id == id)
    }

    /// The entry holding the same content, if any.
    fn find(&self, kind: Kind, data: &[u8], hash: u64) -> io::Result<Option<usize>> {
        for (at, entry) in self.index.entries.iter().enumerate() {
            let item = &entry.item;
            if entry.hash == hash && item.kind == kind && item.size == data.len() as u64 {
                match fs::read(self.path_of(item)) {
                    Ok(old) if old == data => return Ok(Some(at)),
                    Ok(_) => {}
                    Err(err) if err.kind() == io::ErrorKind::NotFound => {}
                    Err(err) => return Err(err),
                }
            }
        }
        Ok(None)
    }

    fn write_entry(
        &mut self,
        kind: Kind,
        mime: &str,
        data: &[u8],
        hash: u64,
        time: u64,
    ) -> io::Result<Entry> {
        let id = self.index.next_id;
        self.index.next_id += 1;
        let size = match kind {
            Kind::Image => content::dimensions(data),
            Kind::Text => None,
        };
        let item = Item {
            id,
            kind,
            mime: mime.to_owned(),
            preview: content::preview(kind, mime, data, size),
            time,
            size: data.len() as u64,
            width: size.map(|(width, _)| width),
            height: size.map(|(_, height)| height),
        };
        write_file(&self.path_of(&item), data, false)?;
        Ok(Entry { item, hash })
    }

    fn path_of(&self, item: &Item) -> PathBuf {
        let extension = match (item.kind, item.mime.as_str()) {
            (Kind::Text, _) => "txt",
            (Kind::Image, "image/png") => "png",
            (Kind::Image, "image/jpeg") => "jpg",
            (Kind::Image, "image/webp") => "webp",
            (Kind::Image, "image/gif") => "gif",
            (Kind::Image, _) => "img",
        };
        self.dir.join(format!("{}.{extension}", item.id))
    }
}

/// Writes `data` to a temporary file readable only by this user and renames
/// it over `path`; with `sync`, once the data is on the disk.
fn write_file(path: &Path, data: &[u8], sync: bool) -> io::Result<()> {
    let mut temporary = path.as_os_str().to_owned();
    temporary.push(".tmp");
    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&temporary)?;
    file.write_all(data)?;
    if sync {
        file.sync_all()?;
    }
    fs::rename(&temporary, path)
}

fn remove_file(path: &Path) -> io::Result<()> {
    match fs::remove_file(path) {
        Err(err) if err.kind() != io::ErrorKind::NotFound => Err(err),
        _ => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::clipboard::content::tests::PNG;

    fn open(dir: &Path) -> Store {
        Store::open(dir.join("skua/clipboard")).unwrap()
    }

    fn ids(store: &Store) -> Vec<u64> {
        store.items().map(|item| item.id).collect()
    }

    fn mode(path: &Path) -> u32 {
        fs::metadata(path).unwrap().permissions().mode() & 0o777
    }

    #[test]
    fn adds_newest_first() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = open(dir.path());
        let first = store.add(Kind::Text, "UTF8_STRING", b"one", 10).unwrap();
        let second = store.add(Kind::Image, "image/png", &PNG, 20).unwrap();
        assert_eq!(first.item.id, 1);
        assert_eq!(second.item.id, 2);
        assert_eq!(ids(&store), [2, 1]);
        assert!(first.dropped.is_empty() && second.dropped.is_empty());

        let image = store.item(2).unwrap();
        assert_eq!(image.kind, Kind::Image);
        assert_eq!((image.width, image.height), (Some(3), Some(2)));
        assert_eq!(image.preview, "PNG 3×2");
        assert_eq!(image.size, PNG.len() as u64);
        assert_eq!(store.read(2).unwrap(), PNG);
        assert_eq!(store.read(1).unwrap(), b"one");
        assert_eq!(store.item(1).unwrap().preview, "one");
    }

    #[test]
    fn the_same_content_moves_to_the_top() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = open(dir.path());
        store.add(Kind::Text, "text/plain", b"one", 10).unwrap();
        store.add(Kind::Text, "text/plain", b"two", 20).unwrap();
        let again = store.add(Kind::Text, "UTF8_STRING", b"one", 30).unwrap();
        assert_eq!(again.item.id, 1);
        assert_eq!(again.item.time, 30);
        assert_eq!(ids(&store), [1, 2]);
        assert_eq!(store.len(), 2);
        let files = fs::read_dir(&store.dir).unwrap().count();
        assert_eq!(files, 3, "two entries and the index");
    }

    #[test]
    fn the_same_hash_with_other_bytes_is_not_a_duplicate() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = open(dir.path());
        store.add(Kind::Text, "text/plain", b"one", 10).unwrap();
        // Pretend another text of the same length had the same hash.
        let hash = content::hash(b"uno");
        store.index.entries[0].hash = hash;
        let other = store.add(Kind::Text, "text/plain", b"uno", 20).unwrap();
        assert_eq!(other.item.id, 2);
        assert_eq!(store.len(), 2);
    }

    #[test]
    fn keeps_at_most_the_limit_and_deletes_the_oldest_files() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = open(dir.path());
        for n in 0..MAX_ITEMS {
            let added = store.add(Kind::Text, "text/plain", n.to_string().as_bytes(), 1);
            assert!(added.unwrap().dropped.is_empty());
        }
        let oldest = store.dir.join("1.txt");
        assert!(oldest.exists());
        let added = store.add(Kind::Text, "text/plain", b"newest", 2).unwrap();
        assert_eq!(added.dropped, [1]);
        assert_eq!(store.len(), MAX_ITEMS);
        assert!(!oldest.exists());
        assert_eq!(
            fs::read_dir(&store.dir).unwrap().count(),
            MAX_ITEMS + 1,
            "one file per entry and the index"
        );
        assert_eq!(store.items().next().unwrap().id, MAX_ITEMS as u64 + 1);
        assert_eq!(store.items().last().unwrap().id, 2);
    }

    #[test]
    fn opening_again_keeps_ids_order_and_settings() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = open(dir.path());
        store.add(Kind::Text, "text/plain", b"one", 10).unwrap();
        store.add(Kind::Image, "image/png", &PNG, 20).unwrap();
        store.add(Kind::Text, "text/plain", b"three", 30).unwrap();
        store.add(Kind::Text, "text/plain", b"one", 40).unwrap();
        store.remove(3).unwrap();
        store.set_paused(true).unwrap();
        let before: Vec<Item> = store.items().cloned().collect();
        drop(store);

        let mut store = open(dir.path());
        assert_eq!(store.items().cloned().collect::<Vec<_>>(), before);
        assert_eq!(ids(&store), [1, 2]);
        assert!(store.paused());
        assert!(!store.imported());
        // Ids are not reused, also after the newest entry was deleted.
        let added = store.add(Kind::Text, "text/plain", b"four", 50).unwrap();
        assert_eq!(added.item.id, 4);
    }

    #[test]
    fn folder_and_files_are_private() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("skua/clipboard");
        fs::create_dir_all(&path).unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
        let mut store = Store::open(path.clone()).unwrap();
        store.add(Kind::Text, "text/plain", b"one", 10).unwrap();
        store.add(Kind::Image, "image/png", &PNG, 20).unwrap();
        assert_eq!(mode(&path), 0o700);
        assert_eq!(mode(&path.join("index.json")), 0o600);
        assert_eq!(mode(&path.join("1.txt")), 0o600);
        assert_eq!(mode(&path.join("2.png")), 0o600);
        assert!(!path.join("index.json.tmp").exists());
    }

    #[test]
    fn opening_drops_broken_entries_and_stray_files() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = open(dir.path());
        store.add(Kind::Text, "text/plain", b"one", 10).unwrap();
        store.add(Kind::Text, "text/plain", b"two", 20).unwrap();
        store.add(Kind::Text, "text/plain", b"three", 30).unwrap();
        let folder = store.dir.clone();
        drop(store);
        fs::remove_file(folder.join("1.txt")).unwrap();
        fs::write(folder.join("2.txt"), b"tw").unwrap();
        fs::write(folder.join("9.png"), b"left over").unwrap();
        fs::write(folder.join("10.txt.tmp"), b"half").unwrap();
        fs::write(folder.join("notes"), b"not ours").unwrap();

        let store = open(dir.path());
        assert_eq!(ids(&store), [3]);
        assert!(!folder.join("9.png").exists());
        assert!(!folder.join("10.txt.tmp").exists());
        assert!(!folder.join("2.txt").exists());
        assert!(folder.join("notes").exists());
        drop(store);
        assert_eq!(ids(&open(dir.path())), [3], "the repaired index was saved");
    }

    #[test]
    fn an_unreadable_index_is_left_alone() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = open(dir.path());
        store.add(Kind::Text, "text/plain", b"one", 10).unwrap();
        let folder = store.dir.clone();
        fs::write(folder.join("index.json"), b"{not json").unwrap();
        assert!(Store::open(folder.clone()).is_err());
        assert!(folder.join("1.txt").exists());

        // What the index holds stays out of the message, which the bar logs.
        fs::write(folder.join("index.json"), br#"{"entries":"a copied text"}"#).unwrap();
        let message = Store::open(folder.clone()).err().unwrap().to_string();
        assert!(message.contains("not a history index"), "{message}");
        assert!(!message.contains("a copied text"), "{message}");
    }

    #[test]
    fn touch_remove_and_clear() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = open(dir.path());
        store.add(Kind::Text, "text/plain", b"one", 10).unwrap();
        store.add(Kind::Text, "text/plain", b"two", 20).unwrap();
        store.add(Kind::Text, "text/plain", b"three", 30).unwrap();
        let moved = store.touch(1, 40).unwrap().unwrap();
        assert_eq!((moved.id, moved.time), (1, 40));
        assert_eq!(ids(&store), [1, 3, 2]);
        assert!(store.touch(99, 50).unwrap().is_none());

        assert!(store.remove(3).unwrap());
        assert!(!store.remove(3).unwrap());
        assert!(!store.dir.join("3.txt").exists());
        assert_eq!(ids(&store), [1, 2]);

        store.clear().unwrap();
        assert_eq!(store.len(), 0);
        assert_eq!(
            fs::read_dir(&store.dir).unwrap().count(),
            1,
            "only the index"
        );
    }

    #[test]
    fn old_entries_go_to_the_bottom() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = open(dir.path());
        store.add(Kind::Text, "text/plain", b"new", 10).unwrap();
        let old = store.add_old(Kind::Text, "text/plain", b"old").unwrap();
        assert_eq!(old.unwrap().time, 0);
        assert!(store
            .add_old(Kind::Text, "text/plain", b"new")
            .unwrap()
            .is_none());
        assert_eq!(ids(&store), [1, 2]);
    }
}
