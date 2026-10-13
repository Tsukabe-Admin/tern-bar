pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Night light: a warm screen (about 4000 K) while on, through wlsunset.
// wlsunset has no fixed-temperature mode, so its day and night temperatures are
// set one kelvin apart (and manual sunrise/sunset times stand in for a
// location): day or night the screen stays at ~4000 K. Stopping the process
// restores normal colours — the compositor drops a gamma client's ramps when it
// leaves. On/off is saved in bar.json.
Singleton {
    id: root

    readonly property bool available: Programs.has("wlsunset")
    readonly property bool on: BarConfig.nightLight

    function toggle() {
        BarConfig.setNightLight(!BarConfig.nightLight);
    }

    Process {
        command: ["wlsunset", "-t", "4000", "-T", "4001", "-S", "06:00", "-s", "18:00"]
        running: root.on && root.available
    }
}
