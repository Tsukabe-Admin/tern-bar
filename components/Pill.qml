import QtQuick
import "../singletons"

// One capsule of the bar. Items declared inside land in a centred Row; the
// capsule brightens while the pointer is anywhere over it, and its width
// follows the (animated) content width so text changes glide.
Rectangle {
    id: pill

    default property alias content: inner.data

    readonly property bool hovered: hoverHandler.hovered
    // The parent row draws one GroupBackground when it has enough pills; the
    // individual fill and rim then fade away so the row reads as one capsule.
    readonly property bool merged: parent !== null && parent.merged === true

    implicitWidth: inner.implicitWidth + 2 * Theme.pillPaddingSide
    implicitHeight: Theme.pillHeight
    radius: Theme.pillRadius
    color: merged ? "transparent" : Theme.popBg
    border.width: merged ? 0 : 1
    border.color: Theme.rim

    Behavior on color { ColorAnimation { duration: Theme.motionSlow } }
    Behavior on border.width { NumberAnimation { duration: Theme.motionSlow } }

    // Visibility changes (a media player appears, the title empties, a pill is
    // hidden) change how crowded the row is; let it recount and merge/unmerge.
    onVisibleChanged: if (parent && parent.recount) parent.recount()

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
