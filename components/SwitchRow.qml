import QtQuick
import "../singletons"

// A labelled switch: the label left, the switch right, the whole row clickable.
Item {
    id: root

    property string text: ""
    property bool on: false

    signal toggled

    implicitHeight: 32
    height: implicitHeight
    width: parent ? parent.width : 0
    opacity: root.enabled ? 1 : 0.4

    Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.right: toggle.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        elide: Text.ElideRight
        color: Theme.t1
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Toggle {
        id: toggle
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        on: root.on
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.toggled()
    }
}
