import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../singletons"
import "../singletons/notifytext.js" as Notify

// One notification, as a toast or in the notification centre: the app's icon
// (or the notification's picture), the app's name and how long ago, the
// summary, the body as plain text, up to three action buttons, and ×. A click
// on the card itself is the notification's default action.
Rectangle {
    id: card

    required property var notification
    // Toasts keep the body short; the centre shows more of it.
    property bool compact: true
    readonly property bool hovered: hover.hovered
    readonly property string image: card.notification ? Notifications.imageFor(card.notification) : ""
    readonly property bool critical: card.notification !== null && card.notification.urgency === NotificationUrgency.Critical

    signal activated
    signal closeClicked
    signal actionClicked(var action)

    width: parent ? parent.width : 360
    height: row.implicitHeight + 24
    radius: Theme.radiusCard
    color: Theme.popBg
    border.width: 1
    border.color: card.critical ? Theme.bad : Theme.rim

    HoverHandler {
        id: hover
    }

    TapHandler {
        onTapped: card.activated()
    }

    Row {
        id: row
        x: 12
        y: 12
        width: card.width - 24
        spacing: 10

        Image {
            id: icon
            visible: card.image !== "" && icon.status !== Image.Error
            width: 32
            height: 32
            source: card.image
            sourceSize.width: 64
            sourceSize.height: 64
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        Column {
            width: row.width - (icon.visible ? icon.width + row.spacing : 0) - closeButton.width - row.spacing
            spacing: 3

            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: card.notification
                    ? (card.notification.appName || "Notification") + "  ·  " + Notifications.timeOf(card.notification) : ""
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.t3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }

            Text {
                textFormat: Text.PlainText
                visible: text !== ""
                width: parent.width
                text: card.notification ? Notify.plain(card.notification.summary) : ""
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 2
                color: Theme.t1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Text {
                textFormat: Text.PlainText
                visible: text !== ""
                width: parent.width
                text: card.notification ? Notify.plain(card.notification.body) : ""
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: card.compact ? 4 : 6
                color: Theme.t2
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }

            Flow {
                readonly property var buttons: card.notification ? Notifications.buttonsOf(card.notification) : []
                visible: buttons.length > 0
                width: parent.width
                topPadding: 4
                spacing: 6

                Repeater {
                    model: parent.buttons

                    Chip {
                        required property var modelData
                        text: modelData.text
                        onClicked: card.actionClicked(modelData)
                    }
                }
            }
        }

        IconButton {
            id: closeButton
            text: "\uf00d"
            fg: Theme.t3
            action: () => card.closeClicked()
        }
    }
}
