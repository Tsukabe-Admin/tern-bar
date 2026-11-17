import QtQuick
import Quickshell
import "../singletons"

// Floating PopupWindow wrapper used by the Pills look. Provides the
// click-outside backstop, exact pill-anchored positioning, and smooth 0.97->1.0
// fade+scale motion on both open and close. The surface covers the screen, so
// it takes input only while the card is open: during the closing fade a click
// goes straight to the window under it.
PopupWindow {
    id: pop

    property var barWindow: null
    property var screenInfo: null
    property Item anchorItem: null
    property string alignMode: "right" // "center" | "right"
    property bool open: false

    default property alias content: slot.data

    property bool shown: false
    property real savedX: 0

    readonly property bool hasAnchor: pop.anchorItem !== null && pop.anchorItem.visible
    readonly property point anchorPos: (pop.open && pop.hasAnchor)
        ? pop.anchorItem.mapToItem(null, 0, 0) : Qt.point(0, 0)

    readonly property real computedX: {
        const w = slot.children.length > 0 ? slot.children[0].implicitWidth : 320;
        if (pop.alignMode === "center") {
            return pop.hasAnchor
                ? Math.max(0, Math.min(pop.anchorPos.x + pop.anchorItem.width / 2 - w / 2, pop.width - w))
                : Math.max(0, Math.round((pop.width - w) / 2));
        }
        return pop.hasAnchor
            ? Math.max(0, Math.min(pop.anchorPos.x + pop.anchorItem.width - w, pop.width - w))
            : Math.max(0, pop.width - w);
    }

    function show() {
        closeTimer.stop();
        pop.savedX = pop.computedX;
        pop.shown = true;
    }

    onOpenChanged: {
        if (pop.open) {
            pop.show();
        } else if (pop.shown) {
            if (Looks.restyling || Theme.isFramed) {
                closeTimer.stop();
                pop.shown = false;
            } else {
                closeTimer.restart();
            }
        }
    }

    // A host made while its popup is already open (a monitor plugged back in)
    // gets no change signal for it.
    Component.onCompleted: if (pop.open) pop.show()

    onComputedXChanged: {
        if (pop.open)
            pop.savedX = pop.computedX;
    }

    Timer {
        id: closeTimer
        interval: Theme.motionFast
        onTriggered: pop.shown = false
    }

    Region {
        id: noInput
    }
    mask: pop.open ? null : noInput

    visible: pop.shown && pop.screenInfo !== null
    anchor.window: pop.barWindow
    anchor.rect.x: 0
    anchor.rect.y: 0
    anchor.rect.width: 1
    anchor.rect.height: 1
    grabFocus: false
    color: "transparent"
    implicitWidth: (pop.screenInfo ? pop.screenInfo.width : 1000) - Theme.barMarginSide
    implicitHeight: (pop.screenInfo ? pop.screenInfo.height : 1000) - Theme.barMarginTop

    MouseArea {
        anchors.fill: parent
        enabled: pop.open
        onClicked: Popups.close()
    }

    Rectangle {
        id: card
        width: slot.children.length > 0 ? slot.children[0].implicitWidth : 320
        height: slot.children.length > 0 ? slot.children[0].implicitHeight : 120
        x: pop.open ? pop.computedX : pop.savedX
        y: Theme.barHeight + 4
        radius: Theme.radiusCard
        color: Theme.popBg
        border.width: 1
        border.color: Theme.rim
        transformOrigin: Item.Top
        opacity: pop.open ? 1 : 0
        scale: pop.open ? 1.0 : 0.97

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.motionFast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveEffects
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: Theme.motionFast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveEffects
            }
        }

        Item {
            id: slot
            anchors.fill: parent
        }
    }
}
