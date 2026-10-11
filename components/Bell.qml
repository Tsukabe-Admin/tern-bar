import QtQuick
import Quickshell
import Quickshell.Io
import "../singletons"

// swaync bell. Streams waybar-format JSON lines from `swaync-client -swb`
// and reconnects if the subscription dies. Notifications stay swaync.
BarItem {
    id: root

    property string alt: ""

    readonly property bool dnd: root.alt.indexOf("dnd") === 0
    readonly property bool notif: root.alt.indexOf("notification") !== -1

    Process {
        id: sub
        command: ["swaync-client", "-swb"]
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    var o = JSON.parse(line);
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

    text: root.notif ? "󱅫" : root.dnd ? "󰂛" : "󰂚"
    fg: root.dnd ? Theme.warn : root.notif ? Theme.t1 : Theme.t2

    onClicked: Quickshell.execDetached(["swaync-client", "-t", "-sw"])
    onRightClicked: Quickshell.execDetached(["swaync-client", "-d", "-sw"])
}
