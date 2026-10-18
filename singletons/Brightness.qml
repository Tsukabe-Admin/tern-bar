pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Screen backlight brightness for Quick Settings and BrightnessOsd.
// Reads the first backlight device in /sys/class/backlight (or
// $TERN_BAR_BACKLIGHT_DIR for testing) and stays quiet on desktop machines
// with no backlight hardware.
Singleton {
    id: root

    readonly property string sysfsDir:
        String(Quickshell.env("TERN_BAR_BACKLIGHT_DIR") || "/sys/class/backlight")

    property bool available: false
    property string device: ""
    property int maxBrightness: 100
    property real value: 1.0

    property int targetPct: 100
    property bool reapply: false
    property bool recheck: false

    function refresh() {
        if (reader.running)
            root.recheck = true;
        else
            reader.running = true;
    }

    function set(fraction) {
        if (!root.available)
            return;
        const clamped = Math.max(0.01, Math.min(1.0, Number(fraction) || 0));
        root.value = clamped;
        root.targetPct = Math.max(1, Math.min(100, Math.round(clamped * 100)));
        Qt.callLater(root.runSetter);
    }

    function step(delta) {
        root.set(root.value + delta);
    }

    function runSetter() {
        if (!root.available)
            return;
        if (setter.running) {
            root.reapply = true;
            return;
        }
        setter.running = true;
    }

    function parseLine(line) {
        const parts = line.trim().split("\t");
        if (parts.length < 3)
            return;
        const dev = parts[0];
        const cur = Number(parts[1]);
        const max = Number(parts[2]);
        if (!dev || !(max > 0) || isNaN(cur))
            return;
        root.device = dev;
        root.maxBrightness = max;
        if (!setter.running)
            root.value = Math.max(0, Math.min(1, cur / max));
        root.available = true;
    }

    Process {
        id: reader
        command: ["sh", "-c",
            "for d in \"$1\"/*; do "
            + "if [ -r \"$d/brightness\" ] && [ -r \"$d/max_brightness\" ]; then "
            + "cur=$(cat \"$d/brightness\" 2>/dev/null || echo 0); "
            + "max=$(cat \"$d/max_brightness\" 2>/dev/null || echo 0); "
            + "if [ \"$max\" -gt 0 ] 2>/dev/null; then "
            + "printf '%s\\t%s\\t%s\\n' \"$(basename \"$d\")\" \"$cur\" \"$max\"; exit 0; "
            + "fi; fi; done",
            "sh", root.sysfsDir]
        stdout: SplitParser {
            onRead: (line) => root.parseLine(line)
        }
        onExited: {
            if (root.recheck) {
                root.recheck = false;
                reader.running = true;
            }
        }
    }

    Process {
        id: setter
        command: ["sh", "-c",
            "dir=$1; dev=$2; pct=$3; max=$4; "
            + "if [ \"$dir\" != \"/sys/class/backlight\" ] && [ -w \"$dir/$dev/brightness\" ]; then "
            + "val=$(( (pct * max + 50) / 100 )); [ \"$val\" -lt 1 ] && val=1; "
            + "printf '%s\\n' \"$val\" > \"$dir/$dev/brightness\"; "
            + "elif command -v brightnessctl >/dev/null 2>&1; then "
            + "brightnessctl -q -c backlight -d \"$dev\" set \"${pct}%\" >/dev/null 2>&1 || true; "
            + "elif [ -w \"$dir/$dev/brightness\" ]; then "
            + "val=$(( (pct * max + 50) / 100 )); [ \"$val\" -lt 1 ] && val=1; "
            + "printf '%s\\n' \"$val\" > \"$dir/$dev/brightness\"; "
            + "fi",
            "sh", root.sysfsDir, root.device, String(root.targetPct), String(root.maxBrightness)]
        onExited: {
            if (root.reapply) {
                root.reapply = false;
                Qt.callLater(root.runSetter);
            } else {
                root.refresh();
            }
        }
    }

    // Watch the brightness file directly (covers both sysfs notifications and
    // test directories under $TERN_BAR_BACKLIGHT_DIR).
    FileView {
        id: watchFile
        path: root.available && root.device !== ""
            ? (root.sysfsDir + "/" + root.device + "/brightness") : ""
        watchChanges: root.available && root.device !== ""
        printErrors: false
        onFileChanged: root.refresh()
    }

    // Kernel backlight uevents for hardware brightness keys on laptops.
    Process {
        id: udevMonitor
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=backlight"]
        running: root.available && root.sysfsDir === "/sys/class/backlight"
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("backlight") !== -1)
                    root.refresh();
            }
        }
    }

    Component.onCompleted: root.refresh()
}
