pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// swaync's state for every bar's bell and for quick settings: one
// `swaync-client -swb` subscription (waybar-format JSON lines), restarted 2 s
// after it dies. Notifications themselves stay swaync's.
//
// swaync is optional: without swaync-client nothing subscribes, and the bell
// and the Do-not-disturb tile hide themselves (Programs.qml finds it). Like the
// other optional programs, that is decided once at start.
Singleton {
    id: root

    readonly property bool available: Programs.has("swaync-client")

    property string alt: ""
    readonly property bool dnd: root.alt.indexOf("dnd") === 0
    readonly property bool hasNotifications: root.alt.indexOf("notification") !== -1

    function start() {
        if (root.available && !sub.running)
            sub.running = true;
    }

    function togglePanel() {
        if (!root.available)
            return;
        Quickshell.execDetached(["swaync-client", "-t", "-sw"]);
    }

    function toggleDnd() {
        if (!root.available)
            return;
        Quickshell.execDetached(["swaync-client", "-d", "-sw"]);
    }

    Process {
        id: sub
        command: ["swaync-client", "-swb"]
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    const o = JSON.parse(line);
                    root.alt = o.alt || "";
                } catch (e) {
                }
            }
        }
        onExited: (exitCode, exitStatus) => restartTimer.restart()
    }

    Timer {
        id: restartTimer
        interval: 2000
        onTriggered: root.start()
    }

    onAvailableChanged: root.start()

    Component.onCompleted: root.start()
}
