import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../singletons"

// System battery pill: reads UPower's aggregate displayDevice (or
// $TERN_BAR_BATTERY_MOCK="85:charging" for testing on desktops) and hides
// itself on desktop machines with no system battery.
BarItem {
    id: root

    readonly property var dev: UPower.displayDevice
    readonly property string mockSpec: String(Quickshell.env("TERN_BAR_BATTERY_MOCK") || "")
    readonly property bool hasMock: root.mockSpec !== ""

    readonly property bool available: root.hasMock
        || (root.dev !== null && root.dev.ready && root.dev.isPresent
            && (root.dev.isLaptopBattery || root.dev.powerSupply))

    readonly property int pct: {
        if (root.hasMock) {
            const n = parseInt(root.mockSpec.split(":")[0], 10);
            return isNaN(n) ? 0 : Math.max(0, Math.min(100, n));
        }
        if (!root.dev)
            return 0;
        return Math.max(0, Math.min(100, Math.round(root.dev.percentage * 100)));
    }

    readonly property int state: {
        if (root.hasMock) {
            const s = (root.mockSpec.split(":")[1] || "").toLowerCase();
            if (s === "charging")
                return UPowerDeviceState.Charging;
            if (s === "pending-charge" || s === "not-charging" || s === "plugged")
                return UPowerDeviceState.PendingCharge;
            if (s === "full")
                return UPowerDeviceState.FullyCharged;
            return UPowerDeviceState.Discharging;
        }
        return root.dev ? root.dev.state : UPowerDeviceState.Unknown;
    }

    readonly property bool onAc: root.hasMock
        ? (root.state === UPowerDeviceState.Charging
            || root.state === UPowerDeviceState.PendingCharge
            || root.state === UPowerDeviceState.FullyCharged)
        : !UPower.onBattery
    readonly property bool charging:
        root.state === UPowerDeviceState.Charging || root.state === UPowerDeviceState.PendingCharge
    readonly property bool full:
        root.state === UPowerDeviceState.FullyCharged || (root.onAc && root.pct >= 99)
    readonly property bool plugged: root.charging || root.full || root.onAc
    readonly property bool low: !root.plugged && root.pct < 20
    readonly property bool critical: !root.plugged && root.pct <= 10

    readonly property string icon: {
        if (root.charging)
            return "󰂄";
        if (root.full)
            return "󰁹";
        if (root.onAc)
            return "󰚥";
        const p = root.pct;
        if (p >= 95) return "󰁹";
        if (p >= 85) return "󰂂";
        if (p >= 75) return "󰂁";
        if (p >= 65) return "󰂀";
        if (p >= 55) return "󰁿";
        if (p >= 45) return "󰁾";
        if (p >= 35) return "󰁽";
        if (p >= 25) return "󰁼";
        if (p >= 15) return "󰁻";
        return "󰁺";
    }

    text: root.icon + " " + root.pct + "%"
    fg: root.critical ? Theme.bad
        : root.low ? Theme.warn
        : root.charging ? Theme.ok
        : Theme.t1
}
