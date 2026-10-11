import QtQuick
import "../singletons"

// Base interactive item inside a pill. Motion: the width glides when the
// label changes (network text, titles, counts), the item springs up on hover
// and dips while pressed, and highlight/colour changes fade instead of
// popping.
Item {
    id: root

    property string text: ""
    property color fg: Theme.t2
    property bool italic: false

    signal clicked()
    signal rightClicked()
    signal scrolled(int delta)

    // The width animates, but the label's text changes instantly; the label is
    // therefore constrained to the item's *current* width and elides while the
    // capsule catches up, so a growing title never renders outside the pill.
    readonly property int sidePadding: 9

    implicitWidth: label.implicitWidth + 2 * root.sidePadding
    implicitHeight: Theme.pillHeight - 2 * Theme.pillPadding

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Theme.motionBase
            easing.type: Easing.OutCubic
        }
    }

    scale: tapHandler.pressed ? 0.94 : (hoverHandler.hovered ? 1.05 : 1.0)

    Behavior on scale {
        SpringAnimation {
            spring: 4
            damping: 0.38
            epsilon: 0.001
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.itemRadius
        color: Theme.hover
        opacity: (hoverHandler.hovered || tapHandler.pressed) ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.motionFast
                easing.type: Easing.OutCubic
            }
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        width: Math.max(0, root.width - 2 * root.sidePadding)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.text
        color: root.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        font.italic: root.italic

        Behavior on color {
            ColorAnimation { duration: Theme.motionFast }
        }
    }

    HoverHandler {
        id: hoverHandler
    }

    TapHandler {
        id: tapHandler
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (eventPoint, button) => {
            if (button === Qt.RightButton)
                root.rightClicked();
            else
                root.clicked();
        }
    }

    WheelHandler {
        onWheel: (event) => root.scrolled(event.angleDelta.y > 0 ? 1 : -1)
    }
}
