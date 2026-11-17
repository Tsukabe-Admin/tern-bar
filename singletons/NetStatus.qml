pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The network pill's data. Reuses the existing network-status.sh helper (same
// JSON contract waybar consumed), but runs it once for the whole shell instead
// of once per screen, and only while the pill is actually on the bar.
//
// The mask is one state file ($XDG_STATE_HOME/skua/show_ip), so the pill
// both watches it and re-reads right after its own toggle: a toggle from
// anywhere (this pill, Mod+P) shows up at once instead of at the next poll,
// and is confirmed with the bar's own message ("IP address hidden").
Singleton {
    id: root

    property string netText: ""
    property string netClass: ""

    // Poll only while the pill is not hidden on the bar. configLoaded guards the
    // moments before bar.json lands (hidden is empty until then).
    readonly property bool wanted:
        BarConfig.configLoaded && BarConfig.hidden.indexOf("network") === -1

    property bool recheck: false

    // Whether the IP is shown (the mask file exists), or null until the file has
    // been looked at once. Only a change after that first look is announced, so
    // starting the bar says nothing.
    property var ipShown: null

    function maskSeen(shown) {
        if (root.ipShown !== null && shown !== root.ipShown) {
            Notice.show(shown ? "\u{F0208}" : "\u{F0209}",
                shown ? "IP address shown" : "IP address hidden");
        }
        root.ipShown = shown;
    }

    function refresh() {
        // The poll looks at the mask file too: its watcher needs the state folder
        // to have existed when the bar started, which a fresh install's has not.
        maskFile.reload();
        // A request that lands while the helper is still running (the toggle
        // just exited, or the state file changed) must not be dropped.
        if (fetch.running)
            root.recheck = true;
        else
            fetch.running = true;
    }

    // The pill's own click.
    function toggleMask() {
        if (!toggle.running)
            toggle.running = true;
    }

    Process {
        id: fetch
        command: [BarConfig.scriptsDir + "/network-status.sh"]
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    var o = JSON.parse(line);
                    root.netText = o.text || "";
                    root.netClass = o.class || "";
                } catch (e) {
                }
            }
        }
        onExited: {
            if (root.recheck) {
                root.recheck = false;
                fetch.running = true;
            }
        }
    }

    // Same watcher contract as Theme.qml's palette: the file's folder has to
    // exist when the bar starts, and the file itself may be absent (that is
    // the "IP hidden" state). A deleted file reports loadFailed, not loaded.
    FileView {
        id: maskFile
        path: BarConfig.stateDir + "/show_ip"
        watchChanges: true
        printErrors: false
        onFileChanged: root.refresh()
        onLoaded: root.maskSeen(true)
        onLoadFailed: (error) => root.maskSeen(false)
    }

    // The pill's own click: re-read the moment the toggle exits, so the
    // response does not depend on the watcher above.
    Process {
        id: toggle
        command: [BarConfig.scriptsDir + "/toggle-ip-privacy.sh"]
        onExited: (exitCode, exitStatus) => root.refresh()
    }

    // Every 4 s: the full refresh while the pill is on the bar, else only a look
    // at the mask file. Its watcher cannot exist when the state folder appeared
    // after the bar started (a first run), and Mod+P must still be confirmed.
    Timer {
        interval: 4000
        repeat: true
        running: true
        onTriggered: {
            if (root.wanted)
                root.refresh();
            else
                maskFile.reload();
        }
    }

    onWantedChanged: {
        if (root.wanted)
            root.refresh();
    }

    Component.onCompleted: {
        if (root.wanted)
            root.refresh();
    }
}
