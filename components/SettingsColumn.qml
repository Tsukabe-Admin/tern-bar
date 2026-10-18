import QtQuick
import "../singletons"

// One of the settings page's three groups: its title, the pills currently in
// it, and the accent line that shows where a dropped pill would land.
Item {
    id: root

    required property string side
    required property string title
    required property Item page

    // Slot the pointer is hovering during a drag, or -1 when it is elsewhere.
    property int dropIndex: -1

    readonly property int count: (BarConfig.layout[root.side] || []).length
    readonly property real availHeight: Math.max(120, root.height - list.y)
    readonly property int gap: root.count > 1
        ? Math.max(2, Math.min(5, Math.floor((root.availHeight - root.count * 22) / (root.count - 1))))
        : 5
    readonly property int rowHeight: root.count > 0
        ? Math.max(18, Math.min(34, Math.floor((root.availHeight - Math.max(0, root.count - 1) * root.gap) / root.count)))
        : 32
    readonly property int pitch: root.rowHeight + root.gap

    // Slot a point lands in: above the first row is slot 0, past the last row is
    // the end of the list. Rounded, so the middle of a gap picks the nearer of
    // the two rows around it.
    function indexAt(scenePos) {
        const p = list.mapFromItem(null, scenePos.x, scenePos.y);
        return Math.max(0, Math.min(root.count, Math.floor((p.y + root.pitch / 2) / root.pitch)));
    }

    Text {
        textFormat: Text.PlainText
        id: titleLabel
        anchors.left: parent.left
        anchors.top: parent.top
        text: root.title
        color: Theme.t2
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
    }

    Column {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: titleLabel.bottom
        anchors.topMargin: 8
        spacing: root.gap

        Repeater {
            model: BarConfig.layout[root.side]

            delegate: SettingsRow {
                required property string modelData
                pillId: modelData
                page: root.page
                width: list.width
                height: root.rowHeight
            }
        }

        // An empty group still offers a visible slot to drop a pill onto.
        Rectangle {
            visible: root.count === 0
            width: list.width
            height: root.rowHeight
            radius: root.rowHeight / 2
            color: "transparent"
            border.width: 1
            border.color: Theme.rim

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "Drop pills here"
                color: Theme.t3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
    }

    Rectangle {
        visible: root.dropIndex >= 0
        x: 0
        y: list.y + root.dropIndex * root.pitch - Math.ceil(root.gap / 2) - 1
        width: list.width
        height: 2
        radius: 1
        color: Theme.accent
    }
}
