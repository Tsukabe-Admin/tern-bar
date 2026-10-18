pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The Tern app is optional: found once at start, on PATH first, then in
// ~/.local/bin. Not found → `installed` stays false and the bar hides the Tern
// pill. The count comes from niri's event stream, never from polling: one entry
// per Tern window, so it changes the moment a window opens or closes, and it
// counts windows rather than the daemon's blocks — one window can hold several
// blocks (a plugin pane beside the shell), and sessions outlive their window.
Singleton {
    id: root

    // Full path to the tern program, or "" when it is not installed.
    property string bin: ""
    readonly property bool installed: root.bin !== ""

    // Tern windows niri currently has open.
    readonly property int windowCount: {
        var n = 0;
        var list = Niri.windows;
        for (var i = 0; i < list.length; i++) {
            if (list[i].app_id === "so.stencil.tern")
                n++;
        }
        return n;
    }

    // `tern` with no argument only hands the launch to a running window, and
    // that window has no directory to put a tab in, so nothing appears. Since
    // 0.7 the CLI opens a *tab* (`tern` typed in a shell, `tern .`), never a
    // window, while a window exists: pass home to make the tab real, and bring
    // an existing window forward so the tab lands on screen.
    readonly property string home: String(Quickshell.env("HOME") || "")

    function open() {
        if (!root.installed)
            return;
        var id = -1;
        for (var i = 0; i < Niri.windows.length; i++) {
            var w = Niri.windows[i];
            if (w.app_id === "so.stencil.tern" && (id < 0 || w.id < id))
                id = w.id;
        }
        if (id >= 0)
            Niri.focusWindow(id);
        Quickshell.execDetached([root.bin, root.home]);
    }

    Process {
        id: locate
        command: ["sh", "-c",
            "command -v tern || { [ -x \"$HOME/.local/bin/tern\" ] && printf '%s\\n' \"$HOME/.local/bin/tern\"; }"]
        stdout: SplitParser {
            onRead: (line) => {
                const path = line.trim();
                if (root.bin === "" && path !== "")
                    root.bin = path;
            }
        }
    }

    Component.onCompleted: locate.running = true
}
