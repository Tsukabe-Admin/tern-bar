import QtQuick
import Quickshell
import Quickshell.Wayland
import "../singletons"

// New notifications, top right under the bar on the focused screen, newest on
// top, at most three. Each goes after its timeout (see
// Notifications.timeoutFor), but not while the pointer is over it. A click is
// the notification's default action, × dismisses it. One window for the whole
// shell; it exists only while a toast shows, and steps aside while the
// notification centre is open (it would sit under it).
PanelWindow {
    id: win

    screen: Popups.screenNamed(Popups.focusedScreenName())
    visible: Notifications.toasts.length > 0 && Popups.open !== "notifications"
    anchors.top: true
    anchors.right: true
    margins.top: Theme.barMarginTop + Theme.barHeight + 8
    margins.right: Theme.barMarginSide
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 360
    implicitHeight: Math.max(1, column.implicitHeight)
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "tern-bar-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Column {
        id: column
        width: win.width
        spacing: 8

        Repeater {
            model: Notifications.toasts

            NotificationCard {
                id: toast
                required property var modelData
                notification: toast.modelData
                compact: true
                onActivated: Notifications.invokeDefault(toast.modelData)
                onCloseClicked: Notifications.dismiss(toast.modelData)
                onActionClicked: (action) => Notifications.invoke(toast.modelData, action)

                Timer {
                    interval: Notifications.timeoutFor(toast.modelData)
                    running: interval > 0 && !toast.hovered
                    onTriggered: Notifications.hideToast(toast.modelData)
                }
            }
        }
    }
}
