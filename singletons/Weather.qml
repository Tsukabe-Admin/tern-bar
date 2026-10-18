pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Shared weather state for the bar's weather pill and the forecast inside
// CalendarPopup. Polled once every 30 minutes while either the weather or clock
// pill is shown on the bar, and seeded immediately from the cached state file
// ($XDG_STATE_HOME/tern-bar/weather.json) so restarts never blank the pill.
Singleton {
    id: root

    property bool available: false
    property real tempC: 0
    property real feelsC: 0
    property string icon: "󰖕"
    property string desc: ""
    property var forecast: []

    // Displayed values follow BarConfig.weatherFahrenheit; the stored numbers
    // stay Celsius, so switching units never needs a new fetch.
    readonly property string temp: root.available ? root.formatTemp(root.tempC) : ""
    readonly property string feelsLike: root.available ? root.formatTemp(root.feelsC) : ""

    readonly property bool wanted: BarConfig.configLoaded
        && (BarConfig.hidden.indexOf("weather") === -1 || BarConfig.hidden.indexOf("clock") === -1)

    property bool recheck: false

    function toCelsius(value) {
        const n = parseFloat(String(value));
        return isFinite(n) ? n : 0;
    }

    // `showUnit` is false for the forecast columns, where the header already
    // shows whether the numbers are °C or °F.
    function formatTemp(celsius, showUnit) {
        const n = Number(celsius);
        if (!isFinite(n))
            return "";
        const value = BarConfig.weatherFahrenheit ? Math.round(n * 9 / 5 + 32) : Math.round(n);
        if (showUnit === false)
            return value + "°";
        return value + (BarConfig.weatherFahrenheit ? "°F" : "°C");
    }

    function applyJson(line) {
        try {
            const o = JSON.parse(line);
            if (!o || typeof o !== "object")
                return;
            // New files carry numbers; old caches only the formatted strings.
            const rawTemp = (o.tempC !== undefined && o.tempC !== null && o.tempC !== "")
                ? o.tempC : o.temp;
            if (rawTemp === undefined || rawTemp === null || rawTemp === "")
                return;
            root.tempC = root.toCelsius(rawTemp);
            const rawFeels = (o.feelsC !== undefined && o.feelsC !== null && o.feelsC !== "")
                ? o.feelsC : o.feelsLike;
            root.feelsC = root.toCelsius(rawFeels !== undefined ? rawFeels : root.tempC);
            root.icon = String(o.icon || "󰖕");
            root.desc = String(o.desc || "");
            const days = Array.isArray(o.forecast) ? o.forecast : [];
            root.forecast = days.map((d) => {
                const copy = Object.assign({}, d);
                copy.maxC = root.toCelsius(d.maxC !== undefined ? d.maxC : d.max);
                copy.minC = root.toCelsius(d.minC !== undefined ? d.minC : d.min);
                return copy;
            });
            root.available = true;
        } catch (e) {
        }
    }

    function refresh() {
        if (fetcher.running)
            root.recheck = true;
        else
            fetcher.running = true;
    }

    FileView {
        id: cacheFile
        path: BarConfig.stateDir + "/weather.json"
        blockLoading: true
        printErrors: false
    }

    Process {
        id: fetcher
        command: [BarConfig.scriptsDir + "/weather.sh"]
        stdout: SplitParser {
            onRead: (line) => root.applyJson(line)
        }
        onExited: (exitCode, exitStatus) => {
            if (root.recheck) {
                root.recheck = false;
                fetcher.running = true;
            } else if (exitCode !== 0 && root.wanted) {
                retryTimer.restart();
            }
        }
    }

    Timer {
        interval: 1800000
        repeat: true
        running: root.wanted
        onTriggered: root.refresh()
    }

    Timer {
        id: retryTimer
        interval: 60000
        onTriggered: {
            if (root.wanted)
                root.refresh();
        }
    }

    onWantedChanged: {
        if (root.wanted)
            root.refresh();
    }

    Component.onCompleted: {
        root.applyJson(cacheFile.text());
        if (root.wanted)
            root.refresh();
    }
}
