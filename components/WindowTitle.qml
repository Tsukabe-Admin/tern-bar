import QtQuick
import "../singletons"

// Focused window title for one output, truncated the way waybar did
// (max-length 40). Hidden when the output has no focused window.
BarItem {
    id: root

    property string output: ""

    readonly property var win: Niri.focusedWindowOn(root.output)
    readonly property string rawTitle: root.win ? (root.win.title || "") : ""
    readonly property bool hasWindow: root.win !== null

    visible: root.hasWindow
    text: root.rawTitle.length > 40 ? root.rawTitle.substr(0, 39) + "…" : root.rawTitle
    fg: Theme.t2
}
