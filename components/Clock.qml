import QtQuick
import "../singletons"

// Same clock data as the waybar module: weekday, date, time.
BarItem {
    id: root

    property var now: new Date()

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    text: "󰃭  " + Qt.formatDateTime(root.now, "ddd, MMM dd  󱑂  HH:mm")
    fg: Theme.t1
}
