pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Shared state for the PokeToken pill and the floating pet.
//
// The engine (a Tern plugin's Python half) rewrites `<data>/status.json` whole on
// every scan; this singleton polls it while Tern is installed, so a machine
// without Tern costs nothing. (Tern without the plugin still polls: the file can
// appear at any scan, and one `cat` per interval is cheaper than missing it.)
// Reads go through `cat` for the same reason SysStats.qml does:
// FileView.reload() is not synchronous, and a stale read here would freeze the
// pill for a whole poll interval.
Singleton {
    id: root

    // Tern's plugin data dir (what the engine was handed as --data). The engine's
    // own status.json carries it back, so the bar never guesses twice.
    readonly property string dataDir: BarConfig.pokeDataDir

    property var status: null
    property bool available: false
    property int generatedAt: 0

    // Offline/stale: older than max(3 * refreshInterval, 900) seconds.
    readonly property bool stale: {
        if (!root.status || root.generatedAt <= 0)
            return true;
        var interval = root.status.refreshInterval || 120;
        var limit = Math.max(3 * interval, 900) * 1000;
        return (Date.now() - root.generatedAt) > limit;
    }

    function load(text) {
        // status.json is pretty-printed, so parse the whole buffer (SplitParser
        // hands us one line at a time; the Process accumulates them with "\n").
        try {
            var obj = JSON.parse(text.trim());
            if (!obj || typeof obj !== "object")
                return;
            root.status = obj;
            root.generatedAt = obj.generatedAt || 0;
            root.available = true;
        } catch (e) {
            // Keep the last good status; a half-written file must not blank the pill.
        }
    }

    // Open the Tern block on the given tab ("" = Home). The engine leaves empty
    // sentinel files in the data dir; the plugin's window half routes them to the
    // block, so no palette interaction is needed.
    function open(tab) {
        if (!Tern.installed)
            return;
        var base = (root.status && root.status.data) ? root.status.data : root.dataDir;
        var file = base + "/open" + (tab ? "-" + tab : "") + ".poke";
        Quickshell.execDetached(["sh", "-c",
            "\"$1\" focus PokeToken >/dev/null 2>&1 || \"$1\" open \"$2\"",
            "sh", Tern.bin, file]);
    }

    // Run one engine command detached (scan --force, act …).
    function run(args) {
        if (!root.status || !root.status.engine)
            return;
        Quickshell.execDetached(["python3", root.status.engine, "--data", root.status.data].concat(args));
    }

    property string buffer: ""

    Process {
        id: poll
        command: ["cat", root.dataDir + "/status.json"]
        stdout: SplitParser {
            onRead: (line) => root.buffer += line + "\n"
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                root.load(root.buffer);
            root.buffer = "";
        }
    }

    Timer {
        interval: 2000
        repeat: true
        // The status file only exists when Tern and its plugin are installed.
        running: Tern.installed
        triggeredOnStart: true
        onTriggered: {
            if (!poll.running) {
                root.buffer = "";
                poll.running = true;
            }
        }
    }
}
