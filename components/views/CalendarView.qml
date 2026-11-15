import QtQuick
import "../../singletons"

// Month calendar and multi-day weather forecast body, shared between the
// classic floating popup and the Frame morphing drawer.
// ‹ › change month, the month title returns to today, the wheel
// scrolls months. Weeks start on the locale's first day.
Item {
    id: view

    property var screenInfo: null
    property bool active: false

    property var today: new Date()
    property int year: view.today.getFullYear()
    property int month: view.today.getMonth()
    // The forecast columns, from today on. `today` is set afresh every time the
    // card opens, so the days and their headings are right at that moment.
    readonly property var days: Weather.daysFrom(view.today)

    // QML's Locale numbers days like JS Date: 0 = Sunday … 6 = Saturday.
    readonly property int firstDay: Qt.locale().firstDayOfWeek
    // 42 dates (6 weeks) starting on the locale's first weekday on or before the 1st.
    readonly property var cells: {
        const first = new Date(view.year, view.month, 1);
        const offset = (first.getDay() - view.firstDay + 7) % 7;
        const out = [];
        for (let i = 0; i < 42; i++)
            out.push(new Date(view.year, view.month, 1 - offset + i));
        return out;
    }

    function goToday() {
        view.today = new Date();
        view.year = view.today.getFullYear();
        view.month = view.today.getMonth();
    }

    function shift(step) {
        const d = new Date(view.year, view.month + step, 1);
        view.year = d.getFullYear();
        view.month = d.getMonth();
    }

    onActiveChanged: {
        if (view.active)
            view.goToday();
    }

    implicitWidth: 7 * 36 + 24
    implicitHeight: col.implicitHeight + 24
    width: view.implicitWidth
    height: view.implicitHeight

    // Grabs presses on empty padding; the wheel switches months.
    MouseArea {
        anchors.fill: parent
        onWheel: (wheel) => view.shift(wheel.angleDelta.y > 0 ? -1 : 1)
    }

    Column {
        id: col
        x: 12
        y: 12
        width: view.implicitWidth - 24
        spacing: 8

        Text {
            textFormat: Text.PlainText
            width: parent.width
            text: Qt.formatDate(view.today, "dddd, d MMMM yyyy")
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
                TapHandler { onTapped: view.shift(-1) }
            }

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: Qt.formatDate(new Date(view.year, view.month, 1), "MMMM yyyy")
                color: Theme.t1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                TapHandler { onTapped: view.goToday() }
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
                TapHandler { onTapped: view.shift(1) }
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
                    text: Qt.locale().dayName((view.firstDay + index) % 7, Locale.NarrowFormat)
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            Repeater {
                model: view.cells

                Item {
                    id: cell
                    required property var modelData
                    readonly property bool isToday: cell.modelData.toDateString() === view.today.toDateString()
                    readonly property bool inMonth: cell.modelData.getMonth() === view.month

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
                        color: cell.isToday ? Theme.accentInk : (cell.inMonth ? Theme.t1 : Theme.t4)
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

            // The condition gets the whole line ("Thunderstorm with hail" is the
            // longest one Open-Meteo gives); "Feels" goes on the units line below,
            // whose left half was empty.
            Item {
                width: parent.width
                height: 24

                Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: parent.right
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
            }

            Item {
                width: parent.width
                height: 16

                Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Weather.feelsLike !== ""
                    text: "Feels " + Weather.feelsLike
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        textFormat: Text.PlainText
                        text: "Units"
                        color: Theme.t4
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: "°C"
                        color: BarConfig.weatherFahrenheit ? Theme.t3 : Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: !BarConfig.weatherFahrenheit

                        TapHandler {
                            onTapped: BarConfig.setWeatherFahrenheit(false)
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: "°F"
                        color: BarConfig.weatherFahrenheit ? Theme.accent : Theme.t3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: BarConfig.weatherFahrenheit

                        TapHandler {
                            onTapped: BarConfig.setWeatherFahrenheit(true)
                        }
                    }
                }
            }

            Row {
                visible: view.days.length > 0
                width: parent.width
                spacing: 4

                Repeater {
                    model: view.days

                    Column {
                        id: dayCol
                        required property var modelData
                        readonly property int count: Math.max(1, view.days.length)
                        width: (col.width - 4 * (dayCol.count - 1)) / dayCol.count
                        spacing: 2

                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: Weather.dayLabel(dayCol.modelData.date, view.today)
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
                            text: Weather.formatTemp(dayCol.modelData.maxC, false)
                                + "/" + Weather.formatTemp(dayCol.modelData.minC, false)
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
