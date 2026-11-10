import QtQuick
import Quickshell.Services.SystemTray
import "../singletons"

// StatusNotifier icons. Left click activates (for an item that is only a menu,
// it opens the menu), right click opens the item's DBusMenu in TrayMenu.qml (a
// QML popup — Qt platform menus cannot attach to layer-shell panels on Wayland).
Row {
    id: root
    spacing: 4
    height: Theme.pillHeight - 2 * Theme.pillPadding

    // The bar panel this tray lives in, plus its screen — TrayMenu needs both to
    // cover the screen for click-outside dismissal.
    property var barWindow: null
    property var screenInfo: null

    Repeater {
        id: trayRepeater
        model: SystemTray.items

        delegate: Item {
            id: delegate
            required property var modelData

            width: 20
            height: 20
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: Theme.itemRadius
                color: hover.hovered ? Theme.hover : "transparent"
            }

            Image {
                anchors.centerIn: parent
                source: delegate.modelData.icon
                sourceSize.width: 16
                sourceSize.height: 16
                fillMode: Image.PreserveAspectFit
            }

            HoverHandler {
                id: hover
            }

            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: (eventPoint, button) => {
                    const item = delegate.modelData;
                    // An item that is only a menu has nothing to activate, so
                    // its menu is what the main click is for.
                    if (button === Qt.RightButton || item.onlyMenu) {
                        if (item.hasMenu)
                            rootMenu.openFor(item.menu, delegate);
                    } else {
                        item.activate();
                    }
                }
            }
        }
    }

    TrayMenu {
        id: rootMenu
        barWindow: root.barWindow
        screenInfo: root.screenInfo
    }
}
