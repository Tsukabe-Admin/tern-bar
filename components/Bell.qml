import QtQuick
import "../singletons"

// swaync bell, from the shared Swaync singleton. Click opens swaync's panel, right click toggles Do Not Disturb.
BarItem {
    id: root

    text: Swaync.hasNotifications ? "󱅫" : Swaync.dnd ? "󰂛" : "󰂚"
    fg: Swaync.dnd ? Theme.warn : Swaync.hasNotifications ? Theme.t1 : Theme.t2

    onClicked: Swaync.togglePanel()
    onRightClicked: Swaync.toggleDnd()
}
