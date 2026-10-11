import QtQuick
import Quickshell
import Quickshell.Io
import "../singletons"

// Reuses the existing network-status.sh helper (same JSON contract waybar
// consumed). Click toggles the IP-privacy mask, right click opens the
// connection editor.
BarItem {
    id: root

    property string netText: ""
    property string netClass: ""

    readonly property bool disconnected: root.netClass.indexOf("disconnected") !== -1
    readonly property bool privacy: root.netClass.indexOf("privacy") !== -1

    function refresh() {
        if (!fetch.running)
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

    onClicked: Quickshell.execDetached([BarConfig.scriptsDir + "/toggle-ip-privacy.sh"])
    onRightClicked: Quickshell.execDetached(["nm-connection-editor"])
}
