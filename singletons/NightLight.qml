pragma Singleton

import QtQuick
import Quickshell

// Night light: a warm screen (4000 K) while on. The bar runs
// `skua-helper night-light` (tools/skua-helper; its lines are described at the
// top of src/night_light.rs) only while the setting is on: the job takes every
// screen's gamma control, and when it ends (the setting turned off, the bar
// quit) the compositor gives the screens their own colours back. On/off is
// saved in bar.json.
Singleton {
    id: root

    readonly property bool available: SkuaHelper.installed
    readonly property bool on: BarConfig.nightLight
    // Kelvin: the colour of the screens' white while on (6500 is normal).
    readonly property int temperature: 4000
    // The screens in the job's last state line: [{ name, state }], state
    // "applied" (warm), "refused" (another program holds that screen's gamma,
    // or it has none) or "waiting"; [] while the job is not running.
    property var screens: []
    // The setting alone does not say whether the screens are warm: the job can
    // fail, and the compositor can refuse a screen. The quick settings tile
    // shows `active`, and `problem` when the setting is on and nothing is warm.
    readonly property bool running: helper.running
    readonly property bool active: helper.running && root.screens.some((s) => s.state === "applied")
    readonly property bool refused: root.screens.length > 0 && root.screens.every((s) => s.state === "refused")
    readonly property string problem: (!root.on || !root.available || root.active) ? ""
        : helper.running && root.refused ? "No gamma control"
        : helper.outdated ? "Update skua-helper"
        : !helper.running ? "Not running"
        : ""

    // The temperature has been sent to the job running now.
    property bool asked: false

    function toggle() {
        BarConfig.setNightLight(!BarConfig.nightLight);
    }

    function handle(message) {
        if (message.event === "state") {
            // A list inside a message reaches here through HelperJob's signal
            // as a Qt sequence, not a JS array (Array.isArray says false), so
            // it is copied into one first.
            root.screens = Array.from(message.outputs || []).filter((o) => o !== null && typeof o === "object").map((o) => ({
                name: String(o.name || ""),
                state: String(o.state || "")
            }));
            // The first state line says the job has found the screens: that
            // is when it can be told what to do with them.
            if (!root.asked) {
                root.asked = true;
                helper.send({ temperature: root.temperature });
            }
        } else if (message.event === "error") {
            console.warn("skua-helper night-light:", message.message);
        }
    }

    HelperJob {
        id: helper
        name: "night-light"
        wanted: root.on
        onReceived: (message) => root.handle(message)
        onStopped: {
            root.asked = false;
            root.screens = [];
        }
    }
}
