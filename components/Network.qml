import QtQuick
import Quickshell
import "../singletons"

// The network pill. Click toggles the IP-privacy mask, right click opens the
// connection editor. The data — and the poll — live in NetStatus, shared by
// every bar.
BarItem {
    id: root

    readonly property bool disconnected: NetStatus.netClass.indexOf("disconnected") !== -1
    readonly property bool privacy: NetStatus.netClass.indexOf("privacy") !== -1

    text: NetStatus.netText
    fg: root.disconnected ? Theme.bad : root.privacy ? Theme.t3 : Theme.t2
    italic: root.privacy

    onClicked: NetStatus.toggleMask()
    onRightClicked: Quickshell.execDetached(["nm-connection-editor"])
}
