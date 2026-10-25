import QtQuick
import Quickshell
import Quickshell.Io
import "../singletons"

// A small looping text animation, drawn in one colour. The frames live in
// assets/ascii/<name>.json, written by tools/ascii/gen.mjs from an ascii.rest
// look (https://github.com/bas3line/ascii), so nothing is computed at runtime:
// this only swaps one string for the next. It stops while it is not visible.
//
//   AsciiArt { name: "waves"; tint: Theme.accent }
Item {
    id: root

    // File stem under assets/ascii. Only lowercase letters, digits and dashes
    // are accepted, because the value can come from bar.json.
    property string name: ""
    property color tint: Theme.accent
    property int pixelSize: 11
    property bool playing: true
    // Playback rate as a multiplier: 2 plays twice as fast.
    property real speed: 1.0

    readonly property bool valid: /^[a-z0-9-]+$/.test(root.name)
    property var frames: []
    property int cols: 1
    property int rows: 1
    property int fps: 10
    property int index: 0

    // The cell is measured, not guessed: a missing glyph or another font would
    // otherwise change the pill's width as the frames change.
    implicitWidth: Math.ceil(root.cols * metrics.advanceWidth("M"))
    implicitHeight: root.rows * root.pixelSize

    function load(text) {
        let data = null;
        try {
            data = JSON.parse(text);
        } catch (e) {
        }
        const ok = data && Array.isArray(data.frames) && data.frames.length > 0
            && data.frames.every(f => typeof f === "string");
        root.frames = ok ? data.frames : [];
        root.cols = ok && data.cols > 0 ? Math.min(120, data.cols) : 1;
        root.rows = ok && data.rows > 0 ? Math.min(12, data.rows) : 1;
        root.fps = ok && data.fps >= 1 && data.fps <= 30 ? data.fps : 10;
        root.index = 0;
    }

    FontMetrics {
        id: metrics
        font.family: Theme.fontFamily
        font.pixelSize: root.pixelSize
    }

    FileView {
        id: file
        path: root.valid ? Quickshell.shellDir + "/assets/ascii/" + root.name + ".json" : ""
        blockLoading: true
        printErrors: false
        onLoaded: root.load(file.text())
    }

    Timer {
        interval: Math.max(16, Math.round(1000 / (root.fps * Math.max(0.1, root.speed))))
        repeat: true
        running: root.playing && root.visible && root.frames.length > 1
        onTriggered: root.index = (root.index + 1) % root.frames.length
    }

    Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.frames.length > 0 ? root.frames[root.index] : ""
        color: root.tint
        font.family: Theme.fontFamily
        font.pixelSize: root.pixelSize
        lineHeight: 1.0
        lineHeightMode: Text.ProportionalHeight

        Behavior on color {
            ColorAnimation { duration: Theme.motionFast }
        }
    }
}
