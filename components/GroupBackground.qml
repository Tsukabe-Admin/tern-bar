import QtQuick
import "../singletons"

// The single capsule behind a merged PillRow. It sits before the rows in child
// order, so the pills paint on top of it. `row` is a PillRow.
Rectangle {
    id: bg

    required property Item row

    x: row.x
    y: row.y
    width: row.width
    height: Theme.pillHeight
    radius: Theme.pillRadius
    color: Theme.popBg
    border.width: 1
    border.color: Theme.rim
    opacity: (!Theme.isFramed && row.merged) ? 1 : 0
    visible: !Theme.isFramed && opacity > 0

    Behavior on opacity {
        enabled: !Looks.restyling
        NumberAnimation { duration: Theme.motionSlow; easing.type: Easing.OutCubic }
    }
}
