import QtQuick
import Quickshell
import "../singletons"

// One launcher result: icon (or glyph), title, subtitle. The keyboard-selected
// row is tinted with the accent; hover only brightens. A power action waiting
// for its second Enter turns red.
Item {
    id: row

    required property var modelData
    required property int index
    property bool selected: false

    signal activated

    readonly property bool armed: row.modelData.kind === "power" && Launcher.armed === row.modelData.action
    readonly property string iconSource: row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""

    width: ListView.view ? ListView.view.width : 0
    height: 44

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Theme.itemRadius
        color: row.selected ? Qt.alpha(Theme.accent, 0.16) : (hover.hovered ? Theme.hover : "transparent")
        border.width: row.selected ? 1 : 0
        border.color: Qt.alpha(Theme.accent, 0.5)
    }

    Item {
        id: iconBox
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24

        Image {
            anchors.fill: parent
            visible: row.iconSource !== ""
            source: row.iconSource
            sourceSize.width: 24
            sourceSize.height: 24
            fillMode: Image.PreserveAspectFit
        }

        Text {
            anchors.centerIn: parent
            visible: row.iconSource === ""
            text: row.modelData.glyph || "\uf2d0"
            color: row.armed ? Theme.bad : Theme.t2
            font.family: Theme.fontFamily
            font.pixelSize: 16
        }
    }

    Column {
        anchors.left: iconBox.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            text: row.modelData.title
            elide: Text.ElideRight
            maximumLineCount: 1
            color: row.armed ? Theme.bad : Theme.t1
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        Text {
            width: parent.width
            visible: text !== ""
            text: row.modelData.subtitle || ""
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Theme.t3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }
    }

    HoverHandler {
        id: hover
    }

    TapHandler {
        onTapped: row.activated()
    }
}
