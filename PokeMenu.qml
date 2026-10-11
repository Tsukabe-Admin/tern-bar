import QtQuick
import Quickshell
import "singletons"

// Right-click menu for the PokeToken pill, rendered like TrayMenu.qml: the popup
// window covers the screen anchored at the bar's top-left corner, only the card is
// interactive, and clicks on the backstop dismiss it (a layer-shell panel cannot
// host an xdg_popup, so Qt's own grab does not work here).
PopupWindow {
    id: menu

    property var barWindow: null
    property var screenInfo: null
    property Item anchorItem: null

    // The popup's own origin is the screen's top-left (niri ignores the layer
    // anchor of a popup under a margins-positioned panel), so the card is placed
    // from the anchor item's *screen* coordinates, supplied by the caller.
    property real anchorX: 0
    property real anchorY: 0

    // [{ text, enabled, action }]; separators are rows with action === "".
    readonly property var rows: {
        var petOn = !!(Poke.status && Poke.status.pet && Poke.status.pet.enabled);
        return [
            { text: menu.summaryText(), enabled: false, action: "" },
            { text: menu.versionText(), enabled: false, action: "" },
            { text: "", enabled: false, action: "separator" },
            { text: "Refresh now", enabled: true, action: "refresh" },
            { text: "Pokédex", enabled: true, action: "dex" },
            { text: "Settings…", enabled: true, action: "settings" },
            { text: petOn ? "Hide floating pet" : "Show floating pet",
              enabled: true, action: "pet" }
        ];
    }

    function versionText() {
        var v = (Poke.status && Poke.status.version) ? Poke.status.version : "";
        return v ? "PokeToken " + v : "PokeToken";
    }

    function summaryText() {
        if (Poke.status && Poke.status.summary)
            return Poke.status.summary;
        return "PokeToken";
    }

    function openFor(item) {
        menu.anchorItem = item;
        if (menu.barWindow) {
            menu.anchor.window = menu.barWindow;
            menu.anchor.rect.x = 0;
            menu.anchor.rect.y = 0;
            menu.anchor.rect.width = 1;
            menu.anchor.rect.height = 1;
        }
        menu.visible = true;
    }

    function trigger(action) {
        switch (action) {
        case "refresh":
            Poke.run(["scan", "--force"]);
            break;
        case "dex":
            Poke.open("dex");
            break;
        case "settings":
            Poke.open("settings");
            break;
        case "pet":
            Poke.run(["act", "pet_toggle"]);
            break;
        }
        menu.visible = false;
    }

    visible: false
    grabFocus: false
    color: "transparent"

    readonly property int cardWidth: 260
    readonly property int cardHeight: content.implicitHeight + 16

    implicitWidth: (menu.screenInfo ? menu.screenInfo.width : 1000) - Theme.barMarginSide
    implicitHeight: (menu.screenInfo ? menu.screenInfo.height : 1000) - Theme.barMarginTop

    MouseArea {
        anchors.fill: parent
        enabled: menu.visible
        onClicked: menu.visible = false
    }

    Rectangle {
        id: card
        x: Math.max(0, Math.min(menu.anchorX, menu.width - width))
        y: Math.max(0, Math.min(menu.anchorY, menu.height - height))
        width: menu.cardWidth
        height: menu.cardHeight
        color: Theme.popBg
        radius: Theme.itemRadius
        border.width: 1
        border.color: Theme.rim

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

            Repeater {
                model: menu.rows

                delegate: Item {
                    id: entryRow
                    required property var modelData

                    width: content.width
                    height: entryRow.modelData.action === "separator" ? 9 : 30

                    Rectangle {
                        visible: entryRow.modelData.action !== "separator"
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 6
                        color: (rowHover.hovered && entryRow.modelData.enabled) ? Theme.hover : "transparent"
                    }

                    Rectangle {
                        visible: entryRow.modelData.action === "separator"
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        height: 1
                        color: Theme.l3
                    }

                    Text {
                        visible: entryRow.modelData.action !== "separator"
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: entryRow.modelData.text
                        elide: Text.ElideRight
                        color: entryRow.modelData.enabled ? Theme.t1 : Theme.t4
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }

                    HoverHandler {
                        id: rowHover
                    }

                    TapHandler {
                        onTapped: {
                            if (entryRow.modelData.enabled)
                                menu.trigger(entryRow.modelData.action);
                        }
                    }
                }
            }
        }
    }
}
