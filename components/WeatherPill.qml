import QtQuick
import "../singletons"

// Current condition icon and temperature on the bar. Left-click opens the
// calendar + multi-day forecast popup; right-click forces a fresh weather fetch.
BarItem {
    id: root

    text: Weather.icon + " " + Weather.temp
    fg: Theme.t1

    onRightClicked: Weather.refresh()
}
