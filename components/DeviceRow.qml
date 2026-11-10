import QtQuick
import "../singletons"

// One row of the quick-settings card's Bluetooth lists: the device's name, a
// short status on the right, and, while the pointer is over the row, an
// optional small button after it (Forget).
Item {
    id: row

    property string label: ""
    property color labelColor: Theme.t1
    property string status: ""
    property color statusColor: Theme.t3
    property string actionText: ""
    // The button stays up and turns red while it waits for a second click.
    property bool actionArmed: false
    readonly property bool hovered: rowHover.hovered

    signal tapped
    signal actionClicked

    width: parent ? parent.width : 0
    height: 32

    Rectangle {
        anchors.fill: parent
        radius: Theme.itemRadius
        color: rowHover.hovered ? Theme.hover : "transparent"
    }

    // Everything left of the button is one target, so a click on the button
    // never also counts as a click on the row.
    Item {
        anchors.left: parent.left
        anchors.right: action.visible ? action.left : parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.right: statusText.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: row.label
            elide: Text.ElideRight
            maximumLineCount: 1
            color: row.labelColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Text {
            textFormat: Text.PlainText
            id: statusText
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: row.status
            color: row.statusColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }

        TapHandler {
            onTapped: row.tapped()
        }
    }

    Rectangle {
        id: action
        visible: row.actionText !== "" && (rowHover.hovered || row.actionArmed)
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: actionLabel.implicitWidth + 16
        height: 24
        radius: height / 2
        color: actionHover.hovered ? Theme.hover : "transparent"
        border.width: 1
        border.color: row.actionArmed ? Theme.bad : Theme.rim

        Text {
            textFormat: Text.PlainText
            id: actionLabel
            anchors.centerIn: parent
            text: row.actionText
            color: row.actionArmed ? Theme.bad : Theme.t2
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }

        HoverHandler {
            id: actionHover
        }

        MouseArea {
            anchors.fill: parent
            onClicked: row.actionClicked()
        }
    }

    HoverHandler {
        id: rowHover
    }
}
