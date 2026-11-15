import QtQuick
import "../../singletons"
import ".."

// Notification centre history and DND controls, shared between the classic
// popup and the Frame morphing drawer.
// Every notification the bar still holds, newest first, with Do Not Disturb
// and Clear all. A click on a card is its default action, × dismisses it, and
// its buttons are its actions.
Item {
    id: view

    property var screenInfo: null
    property bool active: false

    implicitWidth: 380
    implicitHeight: col.implicitHeight + 24
    width: view.implicitWidth
    height: view.implicitHeight

    MouseArea {
        anchors.fill: parent
    }

    Column {
        id: col
        x: 12
        y: 12
        width: view.implicitWidth - 24
        spacing: 10

        Item {
            width: parent.width
            height: dndChip.height

            Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications"
                color: Theme.t1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
            }

            Row {
                anchors.right: parent.right
                spacing: 6

                Chip {
                    id: dndChip
                    text: "Do not disturb"
                    selected: Notifications.dnd
                    onClicked: Notifications.toggleDnd()
                }

                Chip {
                    visible: Notifications.count > 0
                    text: "Clear all"
                    onClicked: Notifications.clear()
                }
            }
        }

        Text {
            textFormat: Text.PlainText
            visible: Notifications.count === 0
            width: parent.width
            height: 48
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "No notifications"
            color: Theme.t3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        Flickable {
            visible: Notifications.count > 0
            width: parent.width
            height: Math.min(list.implicitHeight, (view.screenInfo ? view.screenInfo.height : 1000) * 0.6)
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list
                width: parent.width
                spacing: 8

                Repeater {
                    model: Notifications.history

                    NotificationCard {
                        id: entry
                        required property var modelData
                        notification: entry.modelData
                        compact: false
                        onActivated: Notifications.invokeDefault(entry.modelData)
                        onCloseClicked: Notifications.dismiss(entry.modelData)
                        onActionClicked: (action) => Notifications.invoke(entry.modelData, action)
                    }
                }
            }
        }
    }
}
