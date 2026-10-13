import QtQuick
import "../singletons"

// Tern pill: how many Tern windows are open, read from niri's event stream so
// the number changes the moment one opens or closes. "—" means niri's event
// stream is not connected, so the count is unknown (a bar started without
// NIRI_SOCKET shows no workspaces either).
//   left click  — the capsule morphs out into a new terminal window
//   right click — moves this pill to the end of the next group (saved in bar.json)
Row {
    id: root

    property var launch: null
    property var cycleSide: null

    spacing: 5

    // keeps the live dot off the capsule's rounded end
    Item {
        implicitWidth: 6
        implicitHeight: 1
    }

    Rectangle {
        width: 6
        height: 6
        radius: 3
        color: Tern.windowCount > 0 ? Theme.live : Theme.t4
        anchors.verticalCenter: parent.verticalCenter

        Behavior on color {
            ColorAnimation { duration: Theme.motionBase }
        }
    }

    BarItem {
        text: "Tern " + (Niri.connected ? Tern.windowCount : "—")
        fg: Niri.connected ? Theme.t1 : Theme.t3
        onClicked: {
            if (root.launch)
                root.launch();
        }
        onRightClicked: {
            if (root.cycleSide)
                root.cycleSide();
        }
    }
}
