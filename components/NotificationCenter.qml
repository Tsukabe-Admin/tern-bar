import QtQuick
import Quickshell
import "../singletons"

// The notification centre, under the bell: every notification the bar still
// holds, newest first, with Do Not Disturb and Clear all. Shown while
// Popups.open is "notifications" on this bar's screen. A click on a card is its
// default action, × dismisses it, and its buttons are its actions.
PopupWindow {
    id: pop

    property var barWindow: null
    property var screenInfo: null
    property Item anchorItem: null

    visible: Popups.open === "notifications" && pop.screenInfo !== null
        && Popups.screenName === pop.screenInfo.name
    anchor.window: pop.barWindow
    anchor.rect.x: 0
    anchor.rect.y: 0
    anchor.rect.width: 1
    anchor.rect.height: 1
    grabFocus: false
    color: "transparent"
    implicitWidth: (pop.screenInfo ? pop.screenInfo.width : 1000) - Theme.barMarginSide
    implicitHeight: (pop.screenInfo ? pop.screenInfo.height : 1000) - Theme.barMarginTop

    readonly property bool hasAnchor: pop.anchorItem !== null && pop.anchorItem.visible
    readonly property point anchorPos: (pop.visible && pop.hasAnchor)
        ? pop.anchorItem.mapToItem(null, 0, 0) : Qt.point(0, 0)

    MouseArea {
        anchors.fill: parent
        enabled: pop.visible
        onClicked: Popups.close()
    }

    Rectangle {
        id: card
        width: 380
        height: col.implicitHeight + 24
        x: pop.hasAnchor
            ? Math.max(0, Math.min(pop.anchorPos.x + pop.anchorItem.width - card.width, pop.width - card.width))
            : Math.max(0, pop.width - card.width)
        y: Theme.barHeight + 4
        radius: Theme.radiusCard
        color: Theme.popBg
        border.width: 1
        border.color: Theme.rim

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: col
            x: 12
            y: 12
            width: card.width - 24
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
                height: Math.min(list.implicitHeight, (pop.screenInfo ? pop.screenInfo.height : 1000) * 0.6)
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
}
