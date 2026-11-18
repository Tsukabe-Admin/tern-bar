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
//
// In the Frame look a toast leaves with a short fade, the ones below close up,
// and the stack keeps clear of an open drawer: it moves down below one that
// would lie under it (quick settings, say) and back up when the drawer closes.
PanelWindow {
    id: win

    readonly property string screenName: Popups.focusedScreenName()
    readonly property int topMargin: Theme.isFramed
        ? (Theme.barHeight + Math.max(3, Math.round(Theme.frameThickness / 2)))
        : (Theme.barMarginTop + Theme.barHeight + 8)
    readonly property int rightMargin: Theme.isFramed
        ? (Theme.frameThickness + 4)
        : Theme.barMarginSide
    readonly property int count: Notifications.toasts.length

    // How far below its usual place the stack sits: under the open drawer of
    // this screen, when that drawer reaches into the stack's column. Never so
    // far that a toast would leave the screen.
    readonly property real offset: {
        const drawer = Theme.isFramed ? Popups.drawerOn(win.screenName) : null;
        if (!drawer || !win.screen)
            return 0;
        const right = win.screen.width - win.rightMargin;
        if (drawer.right <= right - win.width || drawer.left >= right)
            return 0;
        const wanted = drawer.bottom + 8 - win.topMargin;
        return Math.max(0, Math.min(wanted, win.height - list.contentHeight));
    }
    property real shownOffset: win.offset

    Behavior on shownOffset {
        enabled: Theme.isFramed && !Looks.restyling
        NumberAnimation {
            duration: Theme.motionSlow
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveSpatial
        }
    }

    // In the Frame look the last toast has a way out to finish.
    onCountChanged: {
        if (win.count === 0 && Theme.isFramed)
            linger.restart();
    }

    Timer {
        id: linger
        interval: Theme.motionBase
    }

    // The window is the whole column down the screen's right edge, and never
    // changes size: the toasts move inside it. A window that grew and shrank
    // with them would cut off the one on its way out, and a compositor that
    // animates a resize (Hyprland) showed a ghost of the old size.
    screen: Popups.screenNamed(win.screenName)
    visible: (win.count > 0 || linger.running) && Popups.open !== "notifications"
    anchors.top: true
    anchors.right: true
    anchors.bottom: true
    margins.top: win.topMargin
    margins.right: win.rightMargin
    margins.bottom: win.rightMargin
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 360
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "skua-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Only the toasts take the pointer, not the rest of the column.
    mask: Region {
        item: list
    }

    ListView {
        id: list
        y: win.shownOffset
        width: win.width
        height: contentHeight
        spacing: 8
        interactive: false

        // A ScriptModel, not the array itself: every arrival, timeout and
        // dismissal replaces the array, and a view given a new array rebuilds
        // every card. The toasts still on screen would play their entrance
        // again and start their timeouts over.
        model: ScriptModel {
            values: Notifications.toasts
        }

        // Quieter than the entrance: a fade and a short step towards the edge.
        remove: Transition {
            enabled: Theme.isFramed && !Looks.restyling
            ParallelAnimation {
                NumberAnimation {
                    property: "opacity"
                    to: 0
                    duration: Theme.motionFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.curveEffects
                }
                NumberAnimation {
                    property: "x"
                    to: 12
                    duration: Theme.motionFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.curveEffects
                }
            }
        }

        displaced: Transition {
            enabled: Theme.isFramed && !Looks.restyling
            NumberAnimation {
                property: "y"
                duration: Theme.motionBase
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveSpatial
            }
        }

        delegate: Item {
            id: toastSlot
            required property var modelData
            width: list.width
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
