pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Bar preferences, persisted to bar.json so the Tern pill can be moved
// between the bar's three groups at runtime (right-click it) without editing
// QML. Values are also fine to edit by hand; the bar reloads on save.
Singleton {
    id: root

    // "left" | "center" | "right"
    property string ternPillSide: "right"

    // The launch morph animates a fullscreen overlay-layer surface. Stay opt-in:
    // on 2026-10-09 a *loop* of those (a temporarily armed test timer, since
    // removed) panicked niri's DRM compositor and logged the session out, so the
    // default is a plain terminal launch. Deliberately not persisted — every
    // reload returns to the safe default.
    property bool morphEnabled: false

    readonly property string configPath: String(Quickshell.env("HOME") || "") + "/.config/quickshell/tern-bar/bar.json"

    function cycleTernPillSide() {
        const order = ["left", "center", "right"];
        const i = order.indexOf(root.ternPillSide);
        root.setTernPillSide(order[(i + 1) % order.length]);
    }

    function setTernPillSide(side) {
        if (side !== "left" && side !== "center" && side !== "right")
            return;
        root.ternPillSide = side;
        file.setText(JSON.stringify({ ternPillSide: side }, null, 2) + "\n");
    }

    FileView {
        id: file
        path: root.configPath
        printErrors: false

        onLoaded: {
            try {
                const o = JSON.parse(file.text());
                if (o && (o.ternPillSide === "left" || o.ternPillSide === "center" || o.ternPillSide === "right"))
                    root.ternPillSide = o.ternPillSide;
            } catch (e) {
            }
        }
    }
}
