import QtQuick
import Quickshell
import "../singletons"

// Pills host: floating translucent top PanelWindow plus animated
// PopoutPopupHost cards anchored beneath each pill.
// The bar is a row of capsules ("pills"), one per group of items, floating on
// a transparent surface. Geometry matches waybar's occupancy exactly: 8px from
// the top, 12px sides, 40px tall, 48px reserved.
PanelWindow {
    id: bar

    property var screenInfo: null
    property BarContent barContent: null
    readonly property var panelWindow: bar

    screen: bar.screenInfo
    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: Theme.barMarginTop
        left: Theme.barMarginSide
        right: Theme.barMarginSide
    }
    exclusiveZone: Theme.exclusiveZone
    implicitHeight: Theme.barHeight
    color: "transparent"

    Item {
        id: barSlot
        anchors.fill: parent
    }

    function attachContent() {
        if (bar.barContent)
            bar.barContent.parent = barSlot;
    }

    onBarContentChanged: bar.attachContent()
    Component.onCompleted: bar.attachContent()
    Component.onDestruction: {
        if (bar.barContent && bar.barContent.parent === barSlot)
            bar.barContent.parent = null;
    }

    // The popups this bar can own (Popups decides which is open, and where).
    CalendarPopup {
        barWindow: bar
        screenInfo: bar.screenInfo
        anchorItem: bar.barContent ? bar.barContent.anchorForPopup("calendar") : null
    }
    MediaPopup {
        barWindow: bar
        screenInfo: bar.screenInfo
        anchorItem: bar.barContent ? bar.barContent.anchorForPopup("media") : null
    }
    QuickSettings {
        barWindow: bar
        screenInfo: bar.screenInfo
        anchorItem: bar.barContent ? bar.barContent.anchorForPopup("quick") : null
    }
    NotificationCenter {
        barWindow: bar
        screenInfo: bar.screenInfo
        anchorItem: bar.barContent ? bar.barContent.anchorForPopup("notifications") : null
    }
}
