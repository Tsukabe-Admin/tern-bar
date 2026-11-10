import QtQuick
import "../singletons"

// Active XKB keyboard layout, from the compositor. Left-click or wheel-down
// switches to the next layout; right-click or wheel-up switches to the previous.
BarItem {
    id: root

    readonly property bool available: Compositor.keyboardLayouts.length > 0 && Compositor.shortKeyboardLayout !== ""

    text: "󰌌 " + Compositor.shortKeyboardLayout
    fg: Theme.t2

    onClicked: Compositor.switchLayoutNext()
    onRightClicked: Compositor.switchLayoutPrev()
    onScrolled: (delta) => {
        if (delta > 0)
            Compositor.switchLayoutPrev();
        else
            Compositor.switchLayoutNext();
    }
}
