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
    margins.top: Theme.isFramed
        ? (Theme.barHeight + Math.max(3, Math.round(Theme.frameThickness / 2)))
        : (Theme.barMarginTop + Theme.barHeight + 8)
    margins.right: Theme.isFramed
        ? (Theme.frameThickness + 4)
        : Theme.barMarginSide
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
            // A ScriptModel, not the array itself: every arrival, timeout and
            // dismissal replaces the array, and a Repeater given a new array
            // rebuilds every card. The toasts still on screen would play their
            // entrance again and start their timeouts over.
            model: ScriptModel {
                values: Notifications.toasts
            }

            Item {
                id: toastSlot
                required property var modelData
                width: column.width
                height: toast.height
                clip: Theme.isFramed

                property real slideX: Theme.isFramed ? 28 : 0
                property real fadeVal: 0

                Component.onCompleted: enterAnim.restart()

                ParallelAnimation {
                    id: enterAnim
                    NumberAnimation {
                        target: toastSlot
                        property: "slideX"
                        to: 0
                        duration: Theme.motionBase
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveSpatial
                    }
                    NumberAnimation {
                        target: toastSlot
                        property: "fadeVal"
                        from: 0
                        to: 1
                        duration: Theme.motionFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveEffects
                    }
                }

                NotificationCard {
                    id: toast
                    x: toastSlot.slideX
                    width: toastSlot.width
                    opacity: toastSlot.fadeVal
                    notification: toastSlot.modelData
                    compact: true
                    onActivated: Notifications.invokeDefault(toastSlot.modelData)
                    onCloseClicked: Notifications.dismiss(toastSlot.modelData)
                    onActionClicked: (action) => Notifications.invoke(toastSlot.modelData, action)

                    Timer {
                        interval: Notifications.timeoutFor(toastSlot.modelData)
                        running: interval > 0 && !toast.hovered
                        onTriggered: Notifications.hideToast(toastSlot.modelData)
                    }
                }
            }
        }
    }
}
