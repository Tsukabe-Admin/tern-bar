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
    // Whether the screen is being warmed, which the setting alone does not say:
    // wlsunset can be killed or fail to start, and when the compositor refuses
    // it the gamma control of an output it prints one line and stays alive with
    // that screen at its normal colours. The quick settings tile shows `active`,
    // and `problem` when the setting is on and the screen is not warm.
    property bool refused: false
    readonly property bool active: proc.running && !root.refused
    readonly property string problem: (!root.on || !root.available || root.active) ? ""
        : root.refused ? "No gamma control" : "Not running"

    function toggle() {
        BarConfig.setNightLight(!BarConfig.nightLight);
    }

    Process {
        id: proc
        command: ["wlsunset", "-t", "4000", "-T", "4001", "-S", "06:00", "-s", "18:00"]
        running: root.on && root.available

        onRunningChanged: {
            if (proc.running)
                root.refused = false;
        }

        stderr: SplitParser {
            onRead: (line) => {
                if (/gamma control of output .* failed/.test(line))
                    root.refused = true;
            }
        }
    }
}
