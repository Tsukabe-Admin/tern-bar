import QtQuick
import Quickshell
import Quickshell.Io
import "../singletons"

// Reuses the existing network-status.sh helper (same JSON contract waybar
// consumed). Click toggles the IP-privacy mask, right click opens the
// connection editor.
//
// The mask is one state file ($XDG_STATE_HOME/tern-bar/hide_ip), so the pill
// both watches it and re-reads right after its own toggle: a toggle from
// anywhere (this pill, Mod+P) shows up at once instead of at the next poll.
BarItem {
    id: root

    property string netText: ""
    property string netClass: ""

    readonly property bool disconnected: root.netClass.indexOf("disconnected") !== -1
    readonly property bool privacy: root.netClass.indexOf("privacy") !== -1

    property bool recheck: false

    function refresh() {
        // A request that lands while the helper is still running (the toggle
        // just exited, or the state file changed) must not be dropped.
        if (fetch.running)
            root.recheck = true;
        else
            fetch.running = true;
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
    // the "IP visible" state).
    FileView {
        id: maskFile
        path: BarConfig.stateDir + "/hide_ip"
        watchChanges: true
        printErrors: false
        onFileChanged: root.refresh()
    }

    // The pill's own click: re-read the moment the toggle exits, so the
    // response does not depend on the watcher above.
    Process {
        id: toggle
        command: [BarConfig.scriptsDir + "/toggle-ip-privacy.sh"]
        onExited: (exitCode, exitStatus) => root.refresh()
    }

    Timer {
        interval: 4000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()

    text: root.netText
    fg: root.disconnected ? Theme.bad : root.privacy ? Theme.t3 : Theme.t2
    italic: root.privacy

    onClicked: {
        if (!toggle.running)
            toggle.running = true;
    }
    onRightClicked: Quickshell.execDetached(["nm-connection-editor"])
}
