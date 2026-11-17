pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "themesync.js" as ThemeSync

// The Wallpaper tab's backend. One settings file, ~/.config/skua/wallpaper.json,
// which this bar is the only reader and writer of, and the two jobs that act on it:
//
//   scripts/wallpaper.sh   puts an image on one screen ("DP-3") or on all of them ("*");
//                          the bar hands it the settings on its command line
//   recolouring            the bar's colours (and matugen's templates), from that
//                          image through matugen or from a theme in themes/presets.json;
//                          the colour work is in themesync.js
//
// Every outside program is a short-lived process; nothing here talks to its internals.
Singleton {
    id: root

    readonly property string home: String(Quickshell.env("HOME") || "")

    // ── Option lists (what the page shows, in display order) ───────────────
    // The values are the ones wallpaper.sh and matugen accept.
    readonly property var fills: ["crop", "fit", "center", "stretch"]
    readonly property var fillNames: ["Crop", "Fit", "Center", "Stretch"]

    readonly property var transitions: ["fade", "wipe", "wave", "grow", "outer", "left", "random", "none"]
    readonly property var transitionNames: ["Fade", "Wipe", "Wave", "Grow", "Shrink", "Slide", "Random", "None"]

    readonly property var schemes: ["scheme-tonal-spot", "scheme-vibrant", "scheme-expressive",
        "scheme-content", "scheme-fidelity", "scheme-fruit-salad", "scheme-rainbow",
        "scheme-neutral", "scheme-monochrome"]
    readonly property var schemeNames: ["Tonal spot", "Vibrant", "Expressive", "Content",
        "Fidelity", "Fruit salad", "Rainbow", "Neutral", "Monochrome"]

    readonly property var rotateChoices: [5, 15, 30, 60, 180]

    readonly property var defaults: ({
        folder: root.home + "/Pictures/Wallpapers",
        wallpapers: {},
        fill: "crop",
        fillColor: "#000000",
        transition: "fade",
        transitionDuration: 1.5,
        colorSource: "wallpaper",
        preset: "catppuccin-mocha",
        scheme: "scheme-tonal-spot",
        contrast: 0,
        favorites: [],
        rotate: false,
        rotateMinutes: 30,
        rotateFavoritesOnly: false,
        sort: "name"
    })

    // ── State ──────────────────────────────────────────────────────────────
    property var settings: root.normalize(null)

    // Every image in settings.folder: { path, name, mtime }.
    property var files: []
    // What the page shows when putting the image up or recolouring failed. One
    // slot each: an "All screens" pick does both, and with a single slot whichever
    // finished last (usually a success) wiped the other one's message.
    property string wallpaperError: ""
    property string themeError: ""
    readonly property string lastError: root.wallpaperError !== "" ? root.wallpaperError : root.themeError

    readonly property var screens: {
        const out = [];
        for (const s of Quickshell.screens)
            out.push(s.name);
        return out;
    }

    // ── Persistence ────────────────────────────────────────────────────────
    // blockWrites: each change is on disk by the time its setter returns.
    FileView {
        id: file
        path: BarConfig.wallpaperStatePath
        blockWrites: true
        printErrors: false

        onLoaded: {
            try {
                root.settings = root.normalize(JSON.parse(file.text()));
            } catch (e) {
                root.settings = root.normalize(null);
            }
            root.restoreOnce();
            root.rescan();
        }

        // No file yet: the defaults are already in place, just fill the grid.
        onLoadFailed: {
            root.restoreOnce();
            root.rescan();
        }
    }

    function save() {
        file.setText(JSON.stringify(root.settings, null, 2) + "\n");
    }

    // Put the saved wallpaper back once per start (login, a restart, a hot
    // reload). With nothing chosen yet the desktop is left alone: the bar only
    // manages the wallpaper once you have picked one.
    property bool restored: false

    function restoreOnce() {
        if (root.restored)
            return;
        root.restored = true;
        if (Object.keys(root.settings.wallpapers).length > 0)
            root.runWallpaper([], false);
    }

    // ── Normalising ────────────────────────────────────────────────────────
    // Every write goes through here, so a hand-edited or truncated file can
    // never leave the page showing a value its own controls cannot express.
    function pickFrom(value, allowed, fallback) {
        return (typeof value === "string" && allowed.indexOf(value) !== -1) ? value : fallback;
    }

    function clampNumber(value, lo, hi, fallback) {
        return (typeof value === "number" && isFinite(value))
            ? Math.max(lo, Math.min(hi, value))
            : fallback;
    }

    function normalize(raw) {
        const d = root.defaults;
        const o = (raw && typeof raw === "object" && !Array.isArray(raw)) ? raw : {};

        const wallpapers = {};
        if (o.wallpapers && typeof o.wallpapers === "object" && !Array.isArray(o.wallpapers)) {
            for (const key of Object.keys(o.wallpapers)) {
                const value = o.wallpapers[key];
                // Absolute paths only: this value is handed to `awww img`, where
                // an option-like string (--help, --foo) would be parsed as a flag.
                if (typeof value === "string" && value.indexOf("/") === 0)
                    wallpapers[key] = value;
            }
        }

        const favorites = [];
        if (Array.isArray(o.favorites)) {
            for (const path of o.favorites) {
                if (typeof path === "string" && path !== "" && favorites.indexOf(path) === -1)
                    favorites.push(path);
            }
        }

        return {
            // An absolute path only: this value is handed to `find` as its
            // first argument, where something like "-delete" would be read as
            // an action.
            folder: (typeof o.folder === "string" && o.folder.indexOf("/") === 0) ? o.folder : d.folder,
            wallpapers: wallpapers,
            fill: root.pickFrom(o.fill, root.fills, d.fill),
            fillColor: (typeof o.fillColor === "string" && /^#[0-9a-fA-F]{6}$/.test(o.fillColor))
                ? o.fillColor : d.fillColor,
            transition: root.pickFrom(o.transition, root.transitions, d.transition),
            transitionDuration: root.clampNumber(o.transitionDuration, 0.5, 3, d.transitionDuration),
            colorSource: root.pickFrom(o.colorSource, ["wallpaper", "preset"], d.colorSource),
            preset: (typeof o.preset === "string" && o.preset !== "") ? o.preset : d.preset,
            scheme: root.pickFrom(o.scheme, root.schemes, d.scheme),
            contrast: root.clampNumber(o.contrast, -1, 1, d.contrast),
            favorites: favorites,
            rotate: o.rotate === true,
            rotateMinutes: (root.rotateChoices.indexOf(o.rotateMinutes) !== -1)
                ? o.rotateMinutes : d.rotateMinutes,
            rotateFavoritesOnly: o.rotateFavoritesOnly === true,
            sort: root.pickFrom(o.sort, ["name", "newest"], d.sort)
        };
    }

    // Replace the settings with a copy carrying `patch`. QML only emits change
    // signals on reassignment, so nothing here ever mutates in place.
    function update(patch) {
        const next = {};
        for (const key of Object.keys(root.settings))
            next[key] = root.settings[key];
        for (const key of Object.keys(patch))
            next[key] = patch[key];
        root.settings = next;
        root.save();
    }

    // ── Queries ────────────────────────────────────────────────────────────

    // The image a screen shows: its own if it has one, else "All screens".
    function current(target) {
        const w = root.settings.wallpapers;
        if (target === "*")
            return w["*"] || "";
        return w[target] || w["*"] || "";
    }

    // Whether a screen has an image of its own rather than following "All screens".
    function hasOwn(output) {
        return !!root.settings.wallpapers[output];
    }

    function screensShowing(path) {
        const out = [];
        for (const name of root.screens) {
            if (root.current(name) === path)
                out.push(name);
        }
        return out;
    }

    function isFavorite(path) {
        return root.settings.favorites.indexOf(path) !== -1;
    }

    // A file:// URL Qt can load. Per-segment encoding keeps spaces and "#" in
    // filenames working.
    function fileUrl(path) {
        if (!path)
            return "";
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    // ── Actions ────────────────────────────────────────────────────────────
    // Each one stores the new settings and then runs whatever has to follow.

    function setWallpaper(target, path) {
        const w = {};
        for (const key of Object.keys(root.settings.wallpapers))
            w[key] = root.settings.wallpapers[key];

        if (target === "*") {
            // An "All screens" pick replaces every screen's own image, so the
            // new one is what you actually see everywhere.
            root.update({ wallpapers: { "*": path } });
            root.runWallpaper([], true);
            if (root.settings.colorSource === "wallpaper")
                root.runThemeSync();
            return;
        }

        w[target] = path;
        root.update({ wallpapers: w });
        root.runWallpaper([target], true);
    }

    // Drop a screen's own image so it follows "All screens" again.
    function followAll(output) {
        const w = {};
        for (const key of Object.keys(root.settings.wallpapers)) {
            if (key !== output)
                w[key] = root.settings.wallpapers[key];
        }
        root.update({ wallpapers: w });
        root.runWallpaper([output], true);
    }

    function setFill(mode) {
        root.update({ fill: mode });
        root.runWallpaper([], true);
    }

    function setFillColor(hex) {
        root.update({ fillColor: hex });
        root.runWallpaper([], true);
    }

    function setTransition(type) {
        root.update({ transition: type });
    }

    function setTransitionDuration(seconds) {
        root.update({ transitionDuration: seconds });
    }

    function toggleFavorite(path) {
        const next = root.settings.favorites.filter(function (p) { return p !== path; });
        if (next.length === root.settings.favorites.length)
            next.push(path);
        root.update({ favorites: next });
    }

    function setSort(order) {
        root.update({ sort: order });
    }

    function setRotate(on) {
        root.update({ rotate: on });
    }

    function setRotateMinutes(minutes) {
        root.update({ rotateMinutes: minutes });
    }

    function setRotateFavoritesOnly(on) {
        root.update({ rotateFavoritesOnly: on });
    }

    function setColorSource(source) {
        root.update({ colorSource: source });
        root.runThemeSync();
    }

    function setPreset(id) {
        // Choosing a theme is also choosing preset mode — that is the whole
        // point of picking one.
        root.update({ colorSource: "preset", preset: id });
        root.runThemeSync();
    }

    function setScheme(scheme) {
        root.update({ scheme: scheme });
        if (root.settings.colorSource === "wallpaper")
            root.runThemeSync();
    }

    function setContrast(value) {
        root.update({ contrast: value });
        if (root.settings.colorSource === "wallpaper")
            root.runThemeSync();
    }

    function setFolder(path) {
        // Absolute paths only, for the same reason normalize() enforces it.
        if (typeof path !== "string" || path.indexOf("/") !== 0)
            return;
        root.update({ folder: path });
        root.rescan();
    }

    // ── Shuffle and rotation ───────────────────────────────────────────────

    // Pick a different image at random out of `candidates`.
    function shuffle(target, candidates) {
        if (!candidates || candidates.length < 2)
            return;
        const currentPath = root.current(target);
        const pool = candidates.filter(function (p) { return p !== currentPath; });
        if (pool.length === 0)
            return;
        root.setWallpaper(target, pool[Math.floor(Math.random() * pool.length)]);
    }

    // The pick of the timer's tick. Only the "All screens" image rotates: a
    // screen with an image of its own keeps it.
    function rotateNow() {
        const all = root.files.map(function (f) { return f.path; });
        let candidates = all;

        if (root.settings.rotateFavoritesOnly) {
            const favorites = all.filter(function (p) { return root.isFavorite(p); });
            // Favourites that leave nothing to rotate between are ignored.
            if (favorites.length >= 2)
                candidates = favorites;
        }

        if (candidates.length < 2)
            return;

        const currentPath = root.settings.wallpapers["*"] || "";
        const pool = candidates.filter(function (p) { return p !== currentPath; });
        if (pool.length === 0)
            return;

        const w = {};
        for (const key of Object.keys(root.settings.wallpapers))
            w[key] = root.settings.wallpapers[key];
        w["*"] = pool[Math.floor(Math.random() * pool.length)];
        root.update({ wallpapers: w });

        const followers = root.screens.filter(function (name) { return !root.hasOwn(name); });
        if (followers.length > 0)
            root.runWallpaper(followers, true);
        if (root.settings.colorSource === "wallpaper")
            root.runThemeSync();
    }

    // The tick looks at the folder again before it picks: the list the grid was
    // built from can be hours old, and an image deleted since then must not be
    // chosen. find.onExited does the picking. The timer runs however few images
    // the last scan found, because its own scan is what notices new ones.
    property bool rotateAfterScan: false

    Timer {
        interval: root.settings.rotateMinutes * 60000
        repeat: true
        running: root.settings.rotate
        onTriggered: {
            root.rotateAfterScan = true;
            root.rescan();
        }
    }

    // awww does not reliably repaint a screen that was unplugged and plugged
    // back in, so re-apply whenever the screen list changes.
    Connections {
        target: Quickshell

        function onScreensChanged() {
            root.runWallpaper([], false);
        }
    }

    // ── Putting the image on screen ────────────────────────────────────────
    // scripts/wallpaper.sh, with the settings spelled out on its command line, so
    // it reads no file. It inherits the bar's environment.

    // A run requested while the script is busy, or null. An empty output list
    // means "every screen" and therefore widens any list.
    property var pendingWallpaper: null

    function runWallpaper(outputs, animate) {
        if (wpProcess.running) {
            const queued = root.pendingWallpaper;
            // The queued run covers what every request asked for. A list only
            // survives while all of them named screens: an empty list means
            // "all screens", which wins.
            let merged = outputs.slice();
            if (queued) {
                if (queued.outputs.length === 0 || outputs.length === 0) {
                    merged = [];
                } else {
                    merged = queued.outputs.slice();
                    for (const name of outputs) {
                        if (merged.indexOf(name) === -1)
                            merged.push(name);
                    }
                }
            }
            root.pendingWallpaper = {
                outputs: merged,
                animate: animate || (queued ? queued.animate : false)
            };
            return;
        }

        // "Every screen" is named screen by screen too, from the screens the bar
        // itself has, on niri and Hyprland alike. Each name carries that screen's
        // own image, or nothing when it follows "All screens".
        const s = root.settings;
        const names = outputs.length > 0 ? outputs : root.screens;
        const command = [BarConfig.scriptsDir + "/wallpaper.sh",
            "--fill", s.fill, "--fill-color", s.fillColor,
            "--transition", s.transition, "--duration", String(s.transitionDuration),
            "--all", s.wallpapers["*"] || ""];
        if (animate)
            command.push("--animate");
        command.push("--");
        for (const name of names)
            command.push(name + "=" + (s.wallpapers[name] || ""));
        wpProcess.command = command;
        wpProcess.running = true;
    }

    Process {
        id: wpProcess

        onExited: (exitCode, exitStatus) => {
            root.wallpaperError = (exitCode === 0) ? ""
                : (exitCode === 3) ? "Install awww to set wallpapers"
                : (exitCode === 7) ? "A chosen image is no longer there: pick another"
                : "Couldn't set the wallpaper (wallpaper.sh exited " + exitCode + ")";
            // The grid may still be showing the image that has gone.
            if (exitCode === 7)
                root.rescan();

            const queued = root.pendingWallpaper;
            root.pendingWallpaper = null;
            if (queued)
                root.runWallpaper(queued.outputs, queued.animate);
        }
    }

    // ── Recolouring ────────────────────────────────────────────────────────
    // The colours come from the "All screens" image (matugen) or from a theme in
    // themes/presets.json (themesync.js). They are written to the state folder as
    // colors.json (every Material role, in matugen's format) and palette.json (the
    // bar's eight colours, which Theme.qml reads), each written whole and renamed
    // into place so nothing reads half a file. Then your matugen templates follow
    // a theme, and last ~/.config/skua/theme-hook.sh runs, if you have one, as
    // theme-hook.sh <colors.json> <label>.
    //
    // One recolour at a time; asking again meanwhile runs it once more afterwards.
    // Each step is a Process run through `sh`, which is always there, so a missing
    // matugen is an exit code and not a Process that never starts (and so never
    // reports back, which would leave themeBusy set for good).
    property bool themeBusy: false
    property bool pendingThemeSync: false
    property string themeLabel: ""
    // A failed write of either file. The write may report after the run has moved
    // on, so finishThemeSync() shows it rather than a success.
    property string saveFailure: ""
    readonly property string colorsPath: BarConfig.stateDir + "/colors.json"

    function runThemeSync() {
        if (root.themeBusy) {
            root.pendingThemeSync = true;
            return;
        }
        root.themeBusy = true;
        root.saveFailure = "";
        const s = root.settings;

        if (s.colorSource === "preset") {
            const preset = ThemeSync.pickPreset(root.presets, s.preset);
            if (!ThemeSync.isUsablePreset(preset)) {
                root.finishThemeSync("Couldn't recolour: themes/presets.json has no usable theme");
                return;
            }
            const colours = JSON.stringify(ThemeSync.colorFile(ThemeSync.presetRoles(preset)), null, 2);
            if (!root.writeColours(colours, preset.name))
                return;
            templatesProcess.command = ["sh", "-c",
                "command -v matugen >/dev/null 2>&1 || exit 0; exec matugen json \"$1\" >/dev/null",
                "skua-theme", root.colorsPath];
            templatesProcess.running = true;
            return;
        }

        // 127: no matugen; 4: no image, or it is gone; 1: matugen failed (its own
        // exit code is not passed on, so it can never be mistaken for the other
        // two). matugen is checked first, so its message is the one shown when
        // both are missing, as before.
        const image = s.wallpapers["*"] || "";
        matugenProcess.label = image.slice(image.lastIndexOf("/") + 1);
        matugenProcess.command = ["sh", "-c",
            "command -v matugen >/dev/null 2>&1 || exit 127; [ -f \"$1\" ] || exit 4; shift; matugen \"$@\" || exit 1",
            "skua-theme", image].concat(ThemeSync.matugenImageArgs(image, s.scheme, s.contrast));
        matugenProcess.running = true;
    }

    // Writes colors.json as given and palette.json cut out of it. False, with the
    // message shown, when the text is not a colour file or a write failed.
    function writeColours(text, label) {
        let palette;
        try {
            palette = ThemeSync.paletteOf(JSON.parse(text));
        } catch (e) {
            root.finishThemeSync("Couldn't recolour: matugen's colour data was not readable");
            return false;
        }
        root.writeFile(colorsFile, root.colorsPath, text);
        root.writeFile(paletteFile, BarConfig.palettePath, JSON.stringify(palette, null, 2) + "\n");
        if (root.saveFailure !== "") {
            root.finishThemeSync("");
            return false;
        }
        root.themeLabel = label;
        Theme.reloadPalette();
        return true;
    }

    // FileView skips a write whose text equals what it last wrote, even when the
    // file has since been deleted, changed by another program, or that write
    // failed (measured on Quickshell 0.3.2). Pointed at the file afresh, it has
    // only what is on disk to compare with, so the write always lands.
    function writeFile(view, path, text) {
        view.path = "";
        view.path = path;
        view.setText(text);
    }

    function runThemeHook() {
        hookProcess.command = ["sh", "-c", "[ -x \"$1\" ] || exit 0; exec \"$@\"", "skua-theme-hook",
            BarConfig.configDir + "/theme-hook.sh", root.colorsPath, root.themeLabel];
        hookProcess.running = true;
    }

    function finishThemeSync(error) {
        root.themeError = error !== "" ? error : root.saveFailure;
        root.themeBusy = false;
        if (root.pendingThemeSync) {
            root.pendingThemeSync = false;
            root.runThemeSync();
        }
    }

    Process {
        id: matugenProcess
        property string label: ""
        stdout: StdioCollector {
            id: matugenOutput
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 127)
                root.finishThemeSync("Install matugen to take colours from the wallpaper, or pick a theme");
            else if (exitCode === 4)
                root.finishThemeSync("Choose an All screens wallpaper first, or pick a theme");
            else if (exitCode !== 0)
                root.finishThemeSync("Couldn't recolour: matugen could not read " + matugenProcess.label);
            else if (root.writeColours(matugenOutput.text, matugenProcess.label))
                root.runThemeHook();
        }
    }

    // A theme's colours through your own matugen templates, when matugen is installed.
    Process {
        id: templatesProcess

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn("Wallpaper: matugen could not render every template; Skua itself was recoloured");
            root.runThemeHook();
        }
    }

    Process {
        id: hookProcess

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn("Wallpaper: theme-hook.sh exited " + exitCode);
            root.finishThemeSync("");
        }
    }

    // No path until writeFile() gives one, so neither file is read for nothing at start.
    FileView {
        id: colorsFile
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onSaveFailed: (error) => root.saveFailure = "Couldn't save the colours (" + FileViewError.toString(error) + ")"
    }

    FileView {
        id: paletteFile
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onSaveFailed: (error) => root.saveFailure = "Couldn't save the colours (" + FileViewError.toString(error) + ")"
    }

    // ── The folder listing ─────────────────────────────────────────────────

    property var scanBuffer: []
    property bool scanPending: false

    function rescan() {
        if (find.running) {
            root.scanPending = true;
            return;
        }
        root.scanBuffer = [];
        find.running = true;
    }

    function addScanLine(line) {
        // "mtime\tpath" from find's -printf, so a path with spaces or tabs in it
        // still splits correctly at the first tab. One file per NUL, not per
        // line: a file name can hold a newline, never a NUL.
        const tab = line.indexOf("\t");
        if (tab < 0)
            return;
        const mtime = parseFloat(line.slice(0, tab));
        const path = line.slice(tab + 1);
        if (path === "")
            return;
        // Nothing binds to the buffer, so appending in place is safe and keeps
        // this O(1) per file instead of copying the whole array each time.
        root.scanBuffer.push({
            path: path,
            name: path.slice(path.lastIndexOf("/") + 1),
            mtime: isFinite(mtime) ? mtime : 0
        });
    }

    Process {
        id: find

        command: ["find", "-L", root.settings.folder, "-type", "f",
            "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png",
            "-o", "-iname", "*.webp", "-o", "-iname", "*.gif", ")", "-not", "-name", ".*",
            "-printf", "%T@\\t%p\\0"]

        stdout: SplitParser {
            splitMarker: "\u0000"
            onRead: (entry) => root.addScanLine(entry)
        }

        onExited: (exitCode, exitStatus) => {
            // An unreadable folder exits non-zero having printed nothing, which
            // is what an empty grid should show anyway. An unchanged listing is
            // left alone, so a scan with nothing new does not rebuild the grid
            // under whoever is scrolling it.
            const found = root.scanBuffer;
            root.scanBuffer = [];
            const same = found.length === root.files.length && found.every(function (f, i) {
                return f.path === root.files[i].path && f.mtime === root.files[i].mtime;
            });
            if (!same)
                root.files = found;
            const again = root.scanPending;
            root.scanPending = false;
            if (again) {
                root.rescan();
            } else if (root.rotateAfterScan) {
                root.rotateAfterScan = false;
                // Rotation may have been switched off while the scan ran.
                if (root.settings.rotate)
                    root.rotateNow();
            }
        }
    }

    // ── Preset themes ──────────────────────────────────────────────────────
    // The list the "matugen off" side of the Colours section shows. It is the
    // same list runThemeSync() expands a theme out of, so the two can never drift.
    readonly property var presets: {
        let raw;
        try {
            raw = JSON.parse(presetsFile.text());
        } catch (e) {
            return [];
        }
        if (!Array.isArray(raw))
            return [];
        return raw.filter(function (p) {
            return p && typeof p.id === "string" && typeof p.name === "string";
        });
    }

    FileView {
        id: presetsFile
        path: BarConfig.themePresetsPath
        blockLoading: true
        printErrors: false
    }
}
