import QtQuick
import Quickshell
import "../singletons"

// Month calendar under the clock. Shown while Popups.open is "calendar" on this
// bar's screen. ‹ › change month, the month title returns to today, the wheel
// scrolls months. Weeks start on the locale's first day.
PopupWindow {
    id: pop

    property var barWindow: null
    property var screenInfo: null
    property Item anchorItem: null

    property var today: new Date()
    property int year: pop.today.getFullYear()
    property int month: pop.today.getMonth()

    visible: Popups.open === "calendar" && pop.screenInfo !== null
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

    onVisibleChanged: {
        if (pop.visible)
            pop.goToday();
    }

    function goToday() {
        pop.today = new Date();
        pop.year = pop.today.getFullYear();
        pop.month = pop.today.getMonth();
    }

    function shift(step) {
        const d = new Date(pop.year, pop.month + step, 1);
        pop.year = d.getFullYear();
        pop.month = d.getMonth();
    }

    // QML's Locale numbers days like JS Date: 0 = Sunday … 6 = Saturday.
    readonly property int firstDay: Qt.locale().firstDayOfWeek

    // 42 dates (6 weeks) starting on the locale's first weekday on or before the 1st.
    readonly property var cells: {
        const first = new Date(pop.year, pop.month, 1);
        const offset = (first.getDay() - pop.firstDay + 7) % 7;
        const out = [];
        for (let i = 0; i < 42; i++)
            out.push(new Date(pop.year, pop.month, 1 - offset + i));
        return out;
    }

    MouseArea {
        anchors.fill: parent
        enabled: pop.visible
        onClicked: Popups.close()
    }

    Rectangle {
        id: card
        width: 7 * 36 + 24
        height: col.implicitHeight + 24
        x: pop.hasAnchor
            ? Math.max(0, Math.min(pop.anchorPos.x + pop.anchorItem.width / 2 - card.width / 2, pop.width - card.width))
            : Math.max(0, Math.round((pop.width - card.width) / 2))
        y: Theme.barHeight + 4
        radius: Theme.radiusCard
        color: Theme.popBg
        border.width: 1
        border.color: Theme.rim

        // Grabs presses on the card's padding; the wheel changes month.
        MouseArea {
            anchors.fill: parent
            onWheel: (wheel) => pop.shift(wheel.angleDelta.y > 0 ? -1 : 1)
        }

        Column {
            id: col
            x: 12
            y: 12
            width: card.width - 24
            spacing: 8

            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: Qt.formatDate(pop.today, "dddd, d MMMM yyyy")
                color: Theme.t2
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Item {
                width: parent.width
                height: 28

                Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    horizontalAlignment: Text.AlignHCenter
                    text: "‹"
                    color: Theme.t2
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 4
                    TapHandler { onTapped: pop.shift(-1) }
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: Qt.formatDate(new Date(pop.year, pop.month, 1), "MMMM yyyy")
                    color: Theme.t1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    TapHandler { onTapped: pop.goToday() }
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    horizontalAlignment: Text.AlignHCenter
                    text: "›"
                    color: Theme.t2
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 4
                    TapHandler { onTapped: pop.shift(1) }
                }
            }

            Grid {
                columns: 7

                Repeater {
                    model: 7

                    Text {
                        textFormat: Text.PlainText
                        width: 36
                        height: 22
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.locale().dayName((pop.firstDay + index) % 7, Locale.NarrowFormat)
                        color: Theme.t3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }

                Repeater {
                    model: pop.cells

                    Item {
                        id: cell
                        required property var modelData
                        readonly property bool isToday: cell.modelData.toDateString() === pop.today.toDateString()
                        readonly property bool inMonth: cell.modelData.getMonth() === pop.month

                        width: 36
                        height: 30

                        Rectangle {
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            radius: 13
                            color: cell.isToday ? Theme.accent : "transparent"
                        }

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: cell.modelData.getDate()
                            color: cell.isToday ? Theme.card : (cell.inMonth ? Theme.t1 : Theme.t4)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: cell.isToday
                        }
                    }
                }
            }

            Column {
                visible: Weather.available
                width: parent.width
                spacing: 8

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.rim
                }

                Item {
                    width: parent.width
                    height: 24

                    Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.right: feelsLabel.visible ? feelsLabel.left : parent.right
                        anchors.rightMargin: feelsLabel.visible ? 8 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.icon + "  " + Weather.temp
                            + (Weather.desc !== "" ? " · " + Weather.desc : "")
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: Theme.t1
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }

                    Text {
                        textFormat: Text.PlainText
                        id: feelsLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Weather.feelsLike !== ""
                        text: "Feels " + Weather.feelsLike
                        color: Theme.t3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }

                Row {
                    visible: Weather.forecast.length > 0
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: Weather.forecast.slice(0, 5)

                        Column {
                            id: dayCol
                            required property var modelData
                            readonly property int count: Math.max(1, Math.min(5, Weather.forecast.length))
                            width: (col.width - 4 * (dayCol.count - 1)) / dayCol.count
                            spacing: 2

                            Text {
                                textFormat: Text.PlainText
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: String(dayCol.modelData.day || "")
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                color: Theme.t2
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: true
                            }

                            Text {
                                textFormat: Text.PlainText
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: String(dayCol.modelData.icon || "󰖕")
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize + 3
                            }

                            Text {
                                textFormat: Text.PlainText
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: String(dayCol.modelData.max || "") + "/" + String(dayCol.modelData.min || "")
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                color: Theme.t3
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }
                    }
                }
            }
        }
    }
}
