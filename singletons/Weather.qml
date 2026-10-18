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
    property string temp: ""
    property string feelsLike: ""
    property string icon: "󰖕"
    property string desc: ""
    property var forecast: []

    readonly property bool wanted: BarConfig.configLoaded
        && (BarConfig.hidden.indexOf("weather") === -1 || BarConfig.hidden.indexOf("clock") === -1)

    property bool recheck: false

    function applyJson(line) {
        try {
            const o = JSON.parse(line);
            if (!o || typeof o !== "object" || !o.temp)
                return;
            root.temp = String(o.temp || "");
            root.feelsLike = String(o.feelsLike || "");
            root.icon = String(o.icon || "󰖕");
            root.desc = String(o.desc || "");
            root.forecast = Array.isArray(o.forecast) ? o.forecast : [];
            root.available = root.temp !== "";
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
