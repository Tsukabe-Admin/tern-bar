pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The Wallpaper tab's backend. One settings file, ~/.config/tern-bar/wallpaper.json,
// which this bar is the only writer of — the scripts only read it — plus the
// two scripts in this repo that act on it:
//
//   scripts/wallpaper.sh    puts an image on one screen ("DP-3") or on all of them ("*")
//   scripts/theme-sync.sh   recolours the bar (and matugen's templates), from that
//                           image or from a preset in themes/presets.json
//
// Both are run as short-lived processes; nothing here talks to their internals.
Singleton {
    id: root

    readonly property string home: String(Quickshell.env("HOME") || "")

    // ── Option lists (what the page shows, in display order) ───────────────
    // The values are the ones wallpaper.sh and theme-sync.sh accept.
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
    property string lastError: ""

    readonly property var screens: {
        const out = [];
        for (const s of Quickshell.screens)
            out.push(s.name);
        return out;
    }

    // ── Persistence ────────────────────────────────────────────────────────
    // blockWrites: the scripts read this file the moment they are started, so a
    // queued asynchronous write would let them read the previous state.
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

    function chooseFolder() {
        if (zenity.running)
            return;
        root.folderChoice = "";
        zenity.command = ["zenity", "--file-selection", "--directory",
            "--title=Wallpaper folder", "--filename=" + root.settings.folder + "/"];
        zenity.running = true;
    }

    property string folderChoice: ""

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

    // The timer's tick. Only the "All screens" image rotates: a screen with an
    // image of its own keeps it.
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

    Timer {
        interval: root.settings.rotateMinutes * 60000
        repeat: true
        running: root.settings.rotate && root.files.length > 1
        onTriggered: root.rotateNow()
    }

    // awww does not reliably repaint a screen that was unplugged and plugged
    // back in, so re-apply whenever the screen list changes.
    Connections {
        target: Quickshell

        function onScreensChanged() {
            root.runWallpaper([], false);
        }
    }

    // ── The scripts ────────────────────────────────────────────────────────
    // One Process per script so an exit code can be attributed. Both inherit the
    // bar's environment, which is where NIRI_SOCKET comes from.

    // A run requested while the process is busy, or null. For the wallpaper, an
    // empty output list means "every screen" and therefore widens any list.
    property var pendingWallpaper: null
    property bool pendingThemeSync: false

    function runWallpaper(outputs, animate) {
        if (wpProcess.running) {
            const queued = root.pendingWallpaper;
            let merged = [];
            // A list only survives if *both* runs named screens: otherwise one
            // of them meant "all screens", which wins.
            if (queued && queued.outputs.length > 0 && outputs.length > 0) {
                merged = queued.outputs.slice();
                for (const name of outputs) {
                    if (merged.indexOf(name) === -1)
                        merged.push(name);
                }
            }
            root.pendingWallpaper = {
                outputs: merged,
                animate: animate || (queued ? queued.animate : false)
            };
            return;
        }

        let command = [BarConfig.scriptsDir + "/wallpaper.sh"];
        if (animate)
            command.push("--animate");
        wpProcess.command = command.concat(outputs);
        wpProcess.running = true;
    }

    function runThemeSync() {
        if (themeProcess.running) {
            root.pendingThemeSync = true;
            return;
        }
        themeProcess.command = [BarConfig.scriptsDir + "/theme-sync.sh"];
        themeProcess.running = true;
    }

    Process {
        id: wpProcess

        onExited: (exitCode, exitStatus) => {
            root.lastError = (exitCode === 0) ? ""
                : (exitCode === 3) ? "Install awww to set wallpapers"
                : (exitCode === 5) ? "Install jq to use the Wallpaper tab"
                : "Couldn't set the wallpaper (wallpaper.sh exited " + exitCode + ")";

            const queued = root.pendingWallpaper;
            root.pendingWallpaper = null;
            if (queued)
                root.runWallpaper(queued.outputs, queued.animate);
        }
    }

    Process {
        id: themeProcess

        onExited: (exitCode, exitStatus) => {
            root.lastError = (exitCode === 0) ? ""
                : (exitCode === 3) ? "Install matugen to take colours from the wallpaper, or pick a theme"
                : (exitCode === 4) ? "Choose an All screens wallpaper first, or pick a theme"
                : (exitCode === 5) ? "Install jq to use the Wallpaper tab"
                : (exitCode === 6) ? "Install python3 to use the built-in themes"
                : "Couldn't recolour (theme-sync.sh exited " + exitCode + ")";
            if (exitCode === 0)
                Theme.reloadPalette();

            if (root.pendingThemeSync) {
                root.pendingThemeSync = false;
                root.runThemeSync();
            }
        }
    }

    Process {
        id: zenity

        stdout: SplitParser {
            onRead: (line) => {
                const picked = line.trim();
                if (root.folderChoice === "" && picked !== "")
                    root.folderChoice = picked;
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && root.folderChoice !== "")
                root.setFolder(root.folderChoice);
            root.folderChoice = "";
        }
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
        // still splits correctly at the first tab.
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
            "-printf", "%T@\\t%p\\n"]

        stdout: SplitParser {
            onRead: (line) => root.addScanLine(line)
        }

        onExited: (exitCode, exitStatus) => {
            // An unreadable folder exits non-zero having printed nothing, which
            // is what an empty grid should show anyway.
            root.files = root.scanBuffer;
            root.scanBuffer = [];
            const again = root.scanPending;
            root.scanPending = false;
            if (again)
                root.rescan();
        }
    }

    // ── Preset themes ──────────────────────────────────────────────────────
    // The list the "matugen off" side of the Colours section shows. It is the
    // same file theme-sync.sh expands roles out of, so the two can never drift.
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
