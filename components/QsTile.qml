import QtQuick
import "../singletons"

// One quick settings toggle: glyph, title, one-line state. Accent-tinted
// while on; dimmed and unclickable while disabled.
Rectangle {
    id: tile

    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property bool on: false

    signal clicked

    width: 154
    height: 56
    radius: 14
    color: tile.on ? Qt.alpha(Theme.accent, 0.18) : Qt.alpha(Theme.t1, 0.04)
    border.width: 1
    border.color: tile.on ? Theme.accent : Theme.rim
    opacity: tile.enabled ? 1 : 0.4

    Behavior on color {
        ColorAnimation { duration: Theme.motionFast }
    }

    Rectangle {
        anchors.fill: parent
        radius: tile.radius
        color: Theme.hover
        opacity: (hover.hovered && tile.enabled) ? 1 : 0
    }

    Text {
        id: glyphText
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        text: tile.glyph
        color: tile.on ? Theme.accent : Theme.t2
        font.family: Theme.fontFamily
        font.pixelSize: 18
    }

    Column {
        anchors.left: glyphText.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            width: parent.width
            text: tile.title
            elide: Text.ElideRight
            color: Theme.t1
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        Text {
            width: parent.width
            text: tile.subtitle
            elide: Text.ElideRight
            color: Theme.t3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }
    }

    HoverHandler {
        id: hover
    }

    // A disabled Item drops the events before the MouseArea sees them.
    MouseArea {
        anchors.fill: parent
        onClicked: tile.clicked()
    }
}
