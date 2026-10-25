pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The ASCII tab's backend: what the animated wallpaper and the bar pill look
// like, and how a wallpaper is rendered.
//
//   assets/ascii/manifest.json   the looks, palettes and speeds on offer, written
//                                by `node tools/ascii/gen.mjs assets`
//   ~/.config/tern-bar/ascii.json  the choices; this singleton is its only writer
//
// The pill's colour and speed apply at once (assets/ascii/pill-*.json are
// tinted and played by components/AsciiArt.qml). The wallpaper is a GIF that
// scripts/ascii-render.sh makes and awww plays, so a change there takes a render.
Singleton {
    id: root

    // ── What is on offer ───────────────────────────────────────────────────
    readonly property var emptyManifest: ({
        looks: [], palettes: [], pillPieces: [],
        wallpaperSpeeds: ["normal"], pillSpeeds: ["normal"], sizes: ["medium"]
    })
    property var manifest: root.emptyManifest

    function parseManifest(text) {
        try {
            const m = JSON.parse(text);
            const lists = ["looks", "palettes", "pillPieces", "wallpaperSpeeds", "pillSpeeds", "sizes"];
            if (m && typeof m === "object" && lists.every(k => Array.isArray(m[k])))
                return m;
        } catch (e) {
        }
        return root.emptyManifest;
    }

    FileView {
        id: manifestFile
        path: Quickshell.shellDir + "/assets/ascii/manifest.json"
        blockLoading: true
        printErrors: false
    }

    // ── Settings ───────────────────────────────────────────────────────────
    readonly property var defaults: ({
        wallpaper: { look: "sea", palette: "theme", custom: "#7aa2f7", speed: "normal", size: "medium", brightness: 0.6 },
        pill: { piece: "waves", color: "theme", custom: "#7aa2f7", speed: "normal" }
    })
    property var settings: root.normalize(null)

    function hasId(list, id) {
        return list.some(e => (typeof e === "string" ? e : e.id) === id);
    }

    function pick(value, list, fallback) {
        return root.hasId(list, value) ? value : fallback;
    }

    function pickColor(value, fallback) {
        return (value === "theme" || value === "custom" || root.hasId(root.manifest.palettes, value)) ? value : fallback;
    }

    function pickHex(value, fallback) {
        return (typeof value === "string" && /^#[0-9a-fA-F]{6}$/.test(value)) ? value : fallback;
    }

    // Anything missing or unknown falls back to the default, so a hand-edited
    // file can never leave the tab or the pill without a valid choice.
    function normalize(raw) {
        const o = (raw && typeof raw === "object") ? raw : {};
        const w = (o.wallpaper && typeof o.wallpaper === "object") ? o.wallpaper : {};
        const p = (o.pill && typeof o.pill === "object") ? o.pill : {};
        const d = root.defaults;
        const m = root.manifest;
        const b = Number(w.brightness);
        return {
            wallpaper: {
                look: root.pick(w.look, m.looks, d.wallpaper.look),
                palette: root.pickColor(w.palette, d.wallpaper.palette),
                custom: root.pickHex(w.custom, d.wallpaper.custom),
                speed: root.pick(w.speed, m.wallpaperSpeeds, d.wallpaper.speed),
                size: root.pick(w.size, m.sizes, d.wallpaper.size),
                brightness: isFinite(b) && w.brightness !== null && w.brightness !== ""
                    ? Math.round(Math.max(0.3, Math.min(1, b)) * 10) / 10
                    : d.wallpaper.brightness
            },
            pill: {
                piece: root.pick(p.piece, m.pillPieces, d.pill.piece),
                color: root.pickColor(p.color, d.pill.color),
                custom: root.pickHex(p.custom, d.pill.custom),
                speed: root.pick(p.speed, m.pillSpeeds, d.pill.speed)
            }
        };
    }

    // Replace the settings with a copy carrying `patch` for one section. QML only
    // signals on reassignment, so nothing here mutates in place.
    function update(section, patch) {
        const next = { wallpaper: {}, pill: {} };
        for (const s of ["wallpaper", "pill"])
            for (const key of Object.keys(root.settings[s]))
                next[s][key] = root.settings[s][key];
        for (const key of Object.keys(patch))
            next[section][key] = patch[key];
        root.settings = root.normalize(next);
        root.save();
    }

    function save() {
        file.setText(JSON.stringify(root.settings, null, 2) + "\n");
    }

    FileView {
        id: file
        path: BarConfig.asciiStatePath
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        root.manifest = root.parseManifest(manifestFile.text());
        let parsed = null;
        try {
            parsed = JSON.parse(file.text());
        } catch (e) {
        }
        root.settings = root.normalize(parsed);
    }

    // ── Colours and speeds for the UI ──────────────────────────────────────

    function paletteEntry(id) {
        return root.manifest.palettes.find(p => p.id === id) || null;
    }

    // Per-channel linear blend of two "#rrggbb" colours, as gen.mjs's mix().
    function mixHex(a, b, amount) {
        let out = "#";
        for (const i of [1, 3, 5]) {
            const from = parseInt(a.slice(i, i + 2), 16);
            const to = parseInt(b.slice(i, i + 2), 16);
            const v = Math.round(Math.max(0, Math.min(255, from + (to - from) * amount)));
            out += v.toString(16).padStart(2, "0");
        }
        return out;
    }

    function tintFor(paletteId, custom) {
        if (paletteId === "theme")
            return Theme.accent;
        if (paletteId === "custom")
            return custom;
        const e = root.paletteEntry(paletteId);
        return e ? e.accent : Theme.accent;
    }

    function backgroundFor(paletteId, custom) {
        if (paletteId === "theme")
            return Theme.card;
        if (paletteId === "custom")
            return root.mixHex("#000000", custom, 0.08);
        const e = root.paletteEntry(paletteId);
        return e ? e.background : Theme.card;
    }

    readonly property color wallpaperTint: root.tintFor(root.settings.wallpaper.palette, root.settings.wallpaper.custom)
    readonly property color wallpaperBackground: root.backgroundFor(root.settings.wallpaper.palette, root.settings.wallpaper.custom)
    readonly property color pillColor: root.tintFor(root.settings.pill.color, root.settings.pill.custom)

    // 8 s divided by the loop length, so a preview moves at about the GIF's pace.
    readonly property real wallpaperSpeedFactor:
        ({ calm: 0.4, slow: 0.667, normal: 1, fast: 1.6 })[root.settings.wallpaper.speed] || 1
    readonly property real pillSpeedFactor:
        ({ slow: 0.5, normal: 1, fast: 2 })[root.settings.pill.speed] || 1

    // ── Setters ────────────────────────────────────────────────────────────
    function setLook(id) { root.update("wallpaper", { look: id }); }
    function setPalette(id) { root.update("wallpaper", { palette: id }); }
    function setCustom(hex) { root.update("wallpaper", { custom: hex }); }
    function setSpeed(id) { root.update("wallpaper", { speed: id }); }
    function setSize(id) { root.update("wallpaper", { size: id }); }
    function setBrightness(v) { root.update("wallpaper", { brightness: v }); }
    function setPillPiece(id) { root.update("pill", { piece: id }); }
    function setPillColor(id) { root.update("pill", { color: id }); }
    function setPillCustom(hex) { root.update("pill", { custom: hex }); }
    function setPillSpeed(id) { root.update("pill", { speed: id }); }

    // Step through the pill's pieces, wrapping: +1 for the next, -1 for the previous.
    function cyclePillPiece(step) {
        const ids = root.manifest.pillPieces.map(p => p.id);
        if (ids.length === 0)
            return;
        const at = Math.max(0, ids.indexOf(root.settings.pill.piece));
        root.setPillPiece(ids[(at + (step < 0 ? ids.length - 1 : 1)) % ids.length]);
    }

    // ── Rendering the wallpaper ────────────────────────────────────────────
    property bool rendering: false
    property string status: ""
    property string lastError: ""
    property string outputPath: ""
    property string stderrTail: ""

    function render() {
        if (root.rendering)
            return;
        const w = root.settings.wallpaper;
        const name = w.look + "-" + (w.palette === "custom" ? "custom-" + w.custom.slice(1).toLowerCase() : w.palette) + ".gif";
        root.outputPath = Wallpaper.settings.folder + "/ascii/" + name;

        let width = 0;
        let height = 0;
        for (const s of Quickshell.screens) {
            width = Math.max(width, s.width);
            height = Math.max(height, s.height);
        }
        if (width <= 0 || height <= 0) {
            width = 3440;
            height = 1440;
        }

        let command = [BarConfig.scriptsDir + "/ascii-render.sh", "wallpaper", w.look,
            "--out", root.outputPath, "--screen", Math.round(width) + "x" + Math.round(height),
            "--palette", w.palette, "--speed", w.speed, "--size", w.size, "--brightness", String(w.brightness)];
        if (w.palette === "custom")
            command = command.concat(["--color", w.custom]);

        root.rendering = true;
        root.lastError = "";
        root.stderrTail = "";
        root.status = "Starting…";
        renderProcess.command = command;
        renderProcess.running = true;
    }

    Process {
        id: renderProcess

        stdout: SplitParser {
            onRead: (line) => {
                const parts = line.trim().split(" ");
                if (parts[0] === "progress" && parts.length === 3)
                    root.status = "Rendering frame " + parts[1] + " of " + parts[2] + "…";
                else if (parts[0] === "encoding")
                    root.status = "Encoding GIF…";
            }
        }

        stderr: SplitParser {
            onRead: (line) => {
                if (line.trim() !== "")
                    root.stderrTail = line.trim();
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.rendering = false;
            if (exitCode === 0) {
                Wallpaper.setWallpaper("*", root.outputPath);
                Wallpaper.rescan();
                root.status = "Set on all screens";
                return;
            }
            root.status = "";
            if (exitCode === 3)
                root.lastError = "Install node to render ASCII wallpapers";
            else if (exitCode === 4)
                root.lastError = "Run npm install in tools/ascii first";
            else if (exitCode === 5)
                root.lastError = "Install ffmpeg to render ASCII wallpapers";
            else
                root.lastError = "Render failed: " + root.stderrTail;
        }
    }
}
