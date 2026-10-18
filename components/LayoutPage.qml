import QtQuick
import "../singletons"

// The bar's layout editor, as the "Layout" tab: one column per group, with every
// pill as a row you can drag between them or switch off. Each change reaches the
// bar at once and is written to bar.json.
//
// The tab's own keyboard handling (Esc, initial focus) lives in SettingsWindow;
// this item only fills whatever space the window gives it.
Item {
    id: page

    anchors.fill: parent

    // Drag state. Positions are in window coordinates; the layout only
    // changes on release, so the delegate survives the whole drag.
    property string dragId: ""
    property point dragPos

    readonly property var columns: [leftCol, centerCol, rightCol]

    function beginDrag(id) {
        page.dragId = id;
    }

    function dragMove(scenePos) {
        page.dragPos = scenePos;
        const t = page.dropTarget(scenePos);
        for (const col of page.columns)
            col.dropIndex = (t && t.side === col.side) ? t.index : -1;
    }

    function endDrag() {
        const t = page.dropTarget(page.dragPos);
        if (t && page.dragId !== "")
            BarConfig.movePill(page.dragId, t.side, t.index);
        page.dragId = "";
        for (const col of page.columns)
            col.dropIndex = -1;
    }

    // Which group the pointer is over, and the slot inside it the pill would
    // land in. A point outside every column — the gaps, the margins, outside
    // the window — cancels the drop.
    function dropTarget(scenePos) {
        for (const col of page.columns) {
            const p = col.mapFromItem(null, scenePos.x, scenePos.y);
            if (p.x >= 0 && p.x <= col.width)
                return { side: col.side, index: col.indexAt(scenePos) };
        }
        return null;
    }

    Column {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.topMargin: 20
        spacing: 4

        Text {
            textFormat: Text.PlainText
            text: "Bar layout"
            color: Theme.t1
            font.family: Theme.fontFamily
            font.pixelSize: 20
            font.bold: true
        }

        Text {
            textFormat: Text.PlainText
            text: "Drag a pill to move it. Click it to show or hide it."
            color: Theme.t2
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }

    Chip {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 24
        anchors.topMargin: 20
        text: "Reset layout"
        onClicked: BarConfig.resetLayout()
    }

    Row {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.topMargin: 16
        anchors.bottomMargin: 20
        spacing: 16

        SettingsColumn {
            id: leftCol
            side: "left"
            title: "Left"
            page: page
            width: (body.width - 32) / 3
            height: body.height
        }

        SettingsColumn {
            id: centerCol
            side: "center"
            title: "Middle"
            page: page
            width: (body.width - 32) / 3
            height: body.height
        }

        SettingsColumn {
            id: rightCol
            side: "right"
            title: "Right"
            page: page
            width: (body.width - 32) / 3
            height: body.height
        }
    }

    // Rides under the pointer during a drag, styled like a row so it reads
    // as the pill itself being carried.
    Rectangle {
        id: ghost
        visible: page.dragId !== ""
        width: leftCol.width
        height: 32
        radius: 16
        color: Theme.popBg
        border.width: 1
        border.color: Theme.accent
        z: 10

        readonly property point at: page.mapFromItem(null, page.dragPos.x, page.dragPos.y)

        x: at.x - width / 2
        y: at.y - height / 2

        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: BarConfig.pillNames[page.dragId] || ""
            color: Theme.t1
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }
    }
}
