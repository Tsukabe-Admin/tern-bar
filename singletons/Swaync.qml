pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// swaync's state for every bar's bell and for quick settings: one
// `swaync-client -swb` subscription (waybar-format JSON lines), restarted 2 s
// after it dies. Notifications themselves stay swaync's.
Singleton {
    id: root

    property string alt: ""
    readonly property bool dnd: root.alt.indexOf("dnd") === 0
    readonly property bool hasNotifications: root.alt.indexOf("notification") !== -1

    function togglePanel() {
        Quickshell.execDetached(["swaync-client", "-t", "-sw"]);
    }

    function toggleDnd() {
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
        onTriggered: {
            if (!sub.running)
                sub.running = true;
        }
    }

    Component.onCompleted: sub.running = true
}
