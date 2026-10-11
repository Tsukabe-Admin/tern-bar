import QtQuick
import Quickshell
import "../singletons"

// Tray menu rendered in QML from a DBusMenu handle.
//
// Why not QsMenuAnchor / SystemTrayItem.display()? Those render a Qt QMenu
// widget whose popup QtWayland can only attach to xdg_surface parents; a
// layer-shell panel (this bar) is not one, so the popup silently fails with
// "popup is not an xdg_popup". Rendering the menu ourselves works everywhere.
//
// Dismissal: `grabFocus: true` (Qt's own popup grab, which dismisses on
// click-outside) needs the same xdg_popup parent and fails on this bar, so the
// menu catches outside clicks itself: the popup window covers the whole screen
// anchored to the bar's top-left corner, and only the card is interactive —
// a click anywhere else lands on the backstop MouseArea and closes the menu.
// (One surface, so there is no stacking to fight with the bar or the windows.)
//
// Placement: the card is drawn in window coordinates — under the clicked tray
// icon, with its top just below the bar (`Theme.barHeight`) — instead of being
// anchored at the icon's top-left, which used to cover the bar's right end.
//
// Submenus drill down in place (stack), with a Back row.
PopupWindow {
    id: menu

    property var stack: []
    // The bar panel this menu belongs to, and the screen it lives on (set by
    // Tray.qml). The window anchor is what keeps the popup on the right output.
    property var barWindow: null
    property var screenInfo: null
    // The clicked tray icon; the card is positioned relative to it.
    property Item anchorItem: null

    readonly property var currentHandle: menu.stack.length > 0 ? menu.stack[menu.stack.length - 1] : null

    readonly property point anchorPos: menu.anchorItem
        ? menu.anchorItem.mapToItem(null, 0, 0) : Qt.point(0, 0)

    function openFor(handle, item) {
        menu.stack = [handle];
        menu.anchorItem = item;
        // Anchor the popup to the bar's top-left corner: window coordinates are
        // then the only coordinate space involved, and one surface covers the
        // whole screen for click-outside dismissal.
        if (menu.barWindow) {
            menu.anchor.window = menu.barWindow;
            menu.anchor.rect.x = 0;
            menu.anchor.rect.y = 0;
            menu.anchor.rect.width = 1;
            menu.anchor.rect.height = 1;
        }
        menu.visible = true;
    }

    function push(handle) {
        var s = menu.stack.slice();
        s.push(handle);
        menu.stack = s;
    }

    function pop() {
        if (menu.stack.length > 1)
            menu.stack = menu.stack.slice(0, menu.stack.length - 1);
        else
            menu.visible = false;
    }

    visible: false
    grabFocus: false
    color: "transparent"

    readonly property int cardWidth: 280
    readonly property int cardHeight: content.implicitHeight + 16

    // The bar's own origin is offset from the screen corner by its margins, so
    // this leaves at most those margins uncovered — far away from the menu.
    implicitWidth: (menu.screenInfo ? menu.screenInfo.width : 1000) - Theme.barMarginSide
    implicitHeight: (menu.screenInfo ? menu.screenInfo.height : 1000) - Theme.barMarginTop

    onVisibleChanged: {
        if (!menu.visible)
            menu.stack = [];
    }

    QsMenuOpener {
        id: opener
        menu: menu.currentHandle
    }

    // Click-outside dismissal. Stays under the card; clicks on the card's empty
    // padding are deliberately not treated as "outside".
    MouseArea {
        anchors.fill: parent
        enabled: menu.visible
        onClicked: menu.visible = false
    }

    Rectangle {
        id: card
        x: Math.max(0, Math.min(menu.anchorPos.x, menu.width - width))
        y: Theme.barHeight + 4
        width: menu.cardWidth
        height: menu.cardHeight
        color: Theme.popBg
        radius: Theme.itemRadius
        border.width: 1
        border.color: Theme.rim

        // Presses on the card's own padding (the 8px top margin, the gaps
        // between rows) must not count as "outside": this no-op area grabs them
        // before they reach the backstop. Row TapHandlers sit above it.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 8
            anchors.leftMargin: 1
            anchors.rightMargin: 1

            Item {
                id: backRow
                visible: menu.stack.length > 1
                width: parent.width
                height: visible ? 28 : 0

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: 6
                    color: backHover.hovered ? Theme.hover : "transparent"
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "‹  Back"
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                HoverHandler {
                    id: backHover
                }

                TapHandler {
                    onTapped: menu.pop()
                }
            }

            Repeater {
                model: opener.children

                delegate: Item {
                    id: entryRow
                    required property var modelData

                    width: content.width
                    height: entryRow.modelData.isSeparator ? 9 : 30

                    Rectangle {
                        visible: !entryRow.modelData.isSeparator
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 6
                        color: (rowHover.hovered && entryRow.modelData.enabled) ? Theme.hover : "transparent"
                    }

                    Rectangle {
                        visible: entryRow.modelData.isSeparator
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        height: 1
                        color: Theme.l3
                    }

                    Text {
                        visible: !entryRow.modelData.isSeparator
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        text: entryRow.modelData.checkState !== Qt.Unchecked ? "✔" : ""
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }

                    Text {
                        visible: !entryRow.modelData.isSeparator
                        anchors.left: parent.left
                        anchors.leftMargin: 36
                        anchors.right: arrowText.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: entryRow.modelData.text
                        elide: Text.ElideRight
                        color: entryRow.modelData.enabled ? Theme.t1 : Theme.t4
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }

                    Text {
                        id: arrowText
                        visible: !entryRow.modelData.isSeparator
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: entryRow.modelData.hasChildren ? "❯" : ""
                        color: Theme.t3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }

                    HoverHandler {
                        id: rowHover
                    }

                    TapHandler {
                        onTapped: {
                            var entry = entryRow.modelData;
                            if (entry.isSeparator || !entry.enabled)
                                return;
                            if (entry.hasChildren) {
                                menu.push(entry);
                            } else {
                                // Activate through QsMenuEntry's QML-visible
                                // `triggered` signal (calling it emits it);
                                // DBusMenuItem's sendTriggered() is a private
                                // C++ slot, invisible to QML, so guarding on it
                                // made every entry click a silent no-op.
                                entry.triggered();
                                menu.visible = false;
                            }
                        }
                    }
                }
            }
        }
    }
}
