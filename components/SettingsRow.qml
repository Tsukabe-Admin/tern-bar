import QtQuick
import "../singletons"

// One pill in the settings page: a grip, the pill's name and an on/off switch.
// Clicking anywhere toggles the pill; dragging it moves it to another slot,
// which the page tracks (the row itself never moves while the drag is live).
Rectangle {
    id: root

    required property string pillId
    required property Item page

    // Read straight from BarConfig so the binding follows the array being
    // replaced, which is how every other part of the bar stays in sync.
    readonly property bool shown: !BarConfig.isHidden(root.pillId)

    height: 36
    radius: 18
    color: Theme.popBg
    border.width: 1
    border.color: Theme.rim
    // The row being dragged fades out and the ghost under the pointer stands in.
    opacity: root.page.dragId === root.pillId ? 0.35 : 1

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.motionFast
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.hover
        opacity: rowHover.hovered ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.motionFast
                easing.type: Easing.OutCubic
            }
        }
    }

    Text {
        textFormat: Text.PlainText
        id: grip
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: "\u2261"
        color: Theme.t3
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Text {
        textFormat: Text.PlainText
        id: name
        anchors.left: grip.right
        anchors.leftMargin: 10
        anchors.right: toggle.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: BarConfig.pillNames[root.pillId] || root.pillId
        elide: Text.ElideRight
        color: root.shown ? Theme.t1 : Theme.t3
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true

        Behavior on color {
            ColorAnimation { duration: Theme.motionFast }
        }
    }

    Toggle {
        id: toggle
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        on: root.shown
    }

    HoverHandler {
        id: rowHover
    }

    // The whole row is the click target; a drag past the threshold cancels the
    // tap, so moving a pill never toggles it.
    TapHandler {
        onTapped: BarConfig.setHidden(root.pillId, root.shown)
    }

    DragHandler {
        target: null

        onActiveChanged: {
            if (active) {
                root.page.beginDrag(root.pillId);
                root.page.dragMove(centroid.scenePosition);
            } else {
                root.page.endDrag();
            }
        }

        onCentroidChanged: {
            if (active)
                root.page.dragMove(centroid.scenePosition);
        }
    }
}
