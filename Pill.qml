import QtQuick
import "singletons"

// One capsule of the bar. Items declared inside land in a centred Row; the
// capsule brightens while the pointer is anywhere over it, and its width
// follows the (animated) content width so text changes glide.
Rectangle {
    id: pill

    default property alias content: inner.data

    readonly property bool hovered: hoverHandler.hovered

    implicitWidth: inner.implicitWidth + 2 * Theme.pillPaddingSide
    implicitHeight: Theme.pillHeight
    radius: Theme.pillRadius
    color: Theme.popBg
    border.width: 1
    border.color: Theme.rim

    HoverHandler {
        id: hoverHandler
    }

    Rectangle {
        anchors.fill: parent
        radius: pill.radius
        color: Theme.hover
        opacity: pill.hovered ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.motionFast
                easing.type: Easing.OutCubic
            }
        }
    }

    Row {
        id: inner
        anchors.centerIn: parent
        spacing: 2
    }
}
