import QtQuick
import "../singletons"

// A capsule button. Every setting on the wallpaper page is picked by selecting
// one of a row of these.
Rectangle {
    id: root

    property string text: ""
    property bool selected: false

    signal clicked

    implicitWidth: label.implicitWidth + 24
    implicitHeight: 30
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: root.selected ? Qt.alpha(Theme.accent, 0.18) : Theme.popBg
    border.width: 1
    border.color: root.selected ? Theme.accent : Theme.rim
    // A disabled chip still shows what is stored; it just cannot be changed.
    opacity: root.enabled ? 1 : 0.4

    Behavior on color {
        ColorAnimation { duration: Theme.motionFast }
    }

    Behavior on border.color {
        ColorAnimation { duration: Theme.motionFast }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.hover
        opacity: (chipHover.hovered && root.enabled) ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.motionFast
                easing.type: Easing.OutCubic
            }
        }
    }

    Text {
        textFormat: Text.PlainText
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.selected ? Theme.t1 : Theme.t2
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true

        Behavior on color {
            ColorAnimation { duration: Theme.motionFast }
        }
    }

    HoverHandler {
        id: chipHover
    }

    // A disabled Item drops the events before the MouseArea sees them.
    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
