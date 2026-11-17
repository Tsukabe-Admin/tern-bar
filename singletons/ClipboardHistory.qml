pragma Singleton

import QtQuick
import Quickshell

// Clipboard history, kept by `skua-helper clipboard` (tools/skua-helper; the
// lines it writes are described at the top of src/clipboard/mod.rs). The job
// watches the clipboard for as long as the bar runs, keeps text and images on
// disk (~/.local/state/skua/clipboard), and puts an entry back on the
// clipboard when the launcher picks one. It then answers every paste itself,
// so neither cliphist nor wl-clipboard is needed.
//
// It leaves out a password a password manager marks secret, text over 1 MB,
// an image over 20 MB, and anything an app takes over 2 s to hand over. It
// keeps at most 500 entries; copying something already kept moves it to the
// top.
//
// The first time it runs, it imports an existing cliphist history once: the
// job remembers that it has, also when there was none to import.
Singleton {
    id: root

    readonly property bool installed: job.installed
    // The installed helper was built from older sources than this copy of the bar.
    readonly property bool outdated: job.outdated
    // The job runs and watches the clipboard.
    property bool active: false
    // New copies are not kept until this is turned off again (setPaused).
    property bool paused: false
    // Newest first: { id, kind: "text" or "image", mime, preview, time, size,
    // width, height }. preview is the start of a text on one line, or an
    // image's format and size; time is in seconds since 1970 (0 for an
    // imported entry); width and height are 0 when unknown.
    property var items: []
    // What the job last said went wrong, while it is not running; "" when it
    // said nothing.
    property string problem: ""

    // Puts a kept entry back on the clipboard. It moves to the top.
    function copy(id) {
        job.send({ copy: id });
    }

    // Puts new text on the clipboard (a calculator answer), and keeps it.
    function copyText(text) {
        job.send({ copyText: String(text) });
    }

    function remove(id) {
        job.send({ delete: id });
    }

    function clear() {
        job.send({ clear: true });
    }

    function setPaused(paused) {
        job.send({ pause: paused === true });
    }

    // Adds the newest 500 entries of a cliphist history below the ones kept.
    function importCliphist() {
        job.send({ import: "cliphist" });
    }

    // One entry from the job, checked field by field: a bad one is left out
    // rather than breaking the launcher's list.
    function entry(item) {
        if (!item || typeof item.id !== "number")
            return null;
        return {
            id: item.id,
            kind: item.kind === "image" ? "image" : "text",
            mime: String(item.mime || ""),
            preview: String(item.preview || ""),
            time: Number(item.time) || 0,
            size: Number(item.size) || 0,
            width: Number(item.width) || 0,
            height: Number(item.height) || 0
        };
    }

    function handle(message) {
        if (message.event === "ready") {
            root.problem = "";
            root.active = true;
            root.paused = message.paused === true;
            job.send({ list: true });
            if (message.imported === false)
                root.importCliphist();
        } else if (message.event === "items") {
            // A list inside a message arrives as a Qt sequence, not an array.
            root.items = Array.from(message.items || []).map(root.entry).filter((item) => item !== null);
        } else if (message.event === "added") {
            const item = root.entry(message.item);
            if (item)
                root.items = [item].concat(root.items.filter((old) => old.id !== item.id));
        } else if (message.event === "removed") {
            root.items = root.items.filter((old) => old.id !== message.id);
        } else if (message.event === "cleared") {
            root.items = [];
        } else if (message.event === "paused") {
            root.paused = message.paused === true;
        } else if (message.event === "error") {
            root.problem = String(message.message || "");
            console.warn("skua-helper clipboard:", root.problem);
        }
        // "skipped" (a copy not kept) and "imported" (followed by "items")
        // need nothing here.
    }

    HelperJob {
        id: job
        name: "clipboard"
        onReceived: (message) => root.handle(message)
        onStopped: {
            root.active = false;
            root.items = [];
        }
    }
}
