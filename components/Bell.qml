import QtQuick
import "../singletons"

// The notification bell: a badge while notifications wait, crossed out while
// Do Not Disturb is on. Click opens the notification centre on this screen,
// right click toggles Do Not Disturb.
BarItem {
    id: root

    property string screenName: ""

    text: Notifications.count > 0 ? "󱅫" : Notifications.dnd ? "󰂛" : "󰂚"
    fg: Notifications.dnd ? Theme.warn : Notifications.count > 0 ? Theme.t1 : Theme.t2

    onClicked: Popups.toggle("notifications", root.screenName)
    onRightClicked: Notifications.toggleDnd()
}
