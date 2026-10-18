import QtQuick
import "../singletons"

// Active XKB keyboard layout from niri's event stream. Left-click or wheel-down
// switches to the next layout; right-click or wheel-up switches to the previous.
BarItem {
    id: root

    readonly property bool available: Niri.keyboardLayouts.length > 0 && Niri.shortKeyboardLayout !== ""

    text: "󰌌 " + Niri.shortKeyboardLayout
    fg: Theme.t2

    onClicked: Niri.switchLayoutNext()
    onRightClicked: Niri.switchLayoutPrev()
    onScrolled: (delta) => {
        if (delta > 0)
            Niri.switchLayoutPrev();
        else
            Niri.switchLayoutNext();
    }
}
