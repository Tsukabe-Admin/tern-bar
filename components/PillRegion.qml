import QtQuick
import Quickshell
import "../singletons"

// One pill's rectangle inside the bar's blur region.
//
// Written as explicit geometry rather than `Region { item: pill }` on purpose:
// BackgroundEffect keeps the rectangle a Region last saw, so a pill that moved
// to another group or stopped being shown would go on blurring the slab it used
// to occupy. Reading the pill's box through properties makes the rectangle
// follow every move, resize and hide instead.
Region {
    id: root

    required property Item pill
    required property string pillId

    readonly property bool shown: root.pill.visible && !BarConfig.isHidden(root.pillId)
    // The pill's box in the bar's own coordinates: its row sits at the bar's
    // top-left, so the row's offset plus the pill's is the whole story.
    readonly property real boxX: root.pill.x + (root.pill.parent ? root.pill.parent.x : 0)
    readonly property real boxY: root.pill.y + (root.pill.parent ? root.pill.parent.y : 0)

    x: root.shown ? root.boxX : 0
    y: root.shown ? root.boxY : 0
    width: root.shown ? root.pill.width : 0
    height: root.shown ? root.pill.height : 0
}
