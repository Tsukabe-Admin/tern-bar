import QtQuick
import "singletons"

// Tern pill: live block count from `tern ls --json`.
//   left click  — the capsule morphs out into a new terminal window
//   right click — moves this pill to the bar's next group (persisted)
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
        color: Tern.liveBlocks > 0 ? Theme.live : Theme.t4
        anchors.verticalCenter: parent.verticalCenter

        Behavior on color {
            ColorAnimation { duration: Theme.motionBase }
        }
    }

    BarItem {
        text: "Tern " + (Tern.available ? Tern.liveBlocks : "—")
        fg: Tern.available ? Theme.t1 : Theme.t3
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
