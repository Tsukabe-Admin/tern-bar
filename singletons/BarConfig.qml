pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Bar preferences, persisted to bar.json: the order of the pills inside the
// bar's three groups ("left", "center", "right") and which of them are hidden.
// Edit it from the settings page — the gear in the tools pill, a right-click on
// the launcher, or Mod+B — or by hand; the bar reloads on save.
Singleton {
    id: root

    // The three groups, left to right on screen.
    readonly property var sides: ["left", "center", "right"]

    // Every pill the bar has. A pill is known here under the same id it uses in
    // BarPanel.pills; anything else in bar.json is ignored.
    readonly property var pillIds: ["launcher", "workspaces", "title", "clock", "media", "poke",
        "resources", "network", "volume", "tray", "tools", "system", "tern"]

    // Display names for the settings page.
    readonly property var pillNames: ({
        launcher: "Launcher", workspaces: "Workspaces", title: "Window title", clock: "Clock",
        media: "Media", poke: "PokeToken", resources: "CPU & memory", network: "Network",
        volume: "Volume", tray: "System tray", tools: "Tools", system: "Notifications & power",
        tern: "Tern"
    })

    // The order the bar ships with — also what "Reset layout" restores. A pill
    // added to the bar in future lands in the group it appears in here.
    readonly property var defaultLayout: ({
        left: ["launcher", "workspaces", "title"],
        center: ["clock", "media"],
        right: ["poke", "resources", "network", "volume", "tray", "tools", "system", "tern"]
    })

    // Current layout: { left: [pillId], center: [pillId], right: [pillId] }.
    property var layout: root.normalize(null, "")
    // Pills that keep their slot in the layout but are not shown on the bar.
    property var hidden: []
    // Whether the settings page is open, and which of its two tabs it shows.
    // Neither is persisted, so a reload closes the page on the Layout tab.
    property bool settingsOpen: false
    property string settingsTab: "layout"

    // The launch morph animates a fullscreen overlay-layer surface. Stay opt-in:
    // on 2026-10-09 a *loop* of those (a temporarily armed test timer, since
    // removed) panicked niri's DRM compositor and logged the session out, so the
    // default is a plain terminal launch. Deliberately not persisted — every
    // reload returns to the safe default.
    property bool morphEnabled: false

    // ── Layout ─────────────────────────────────────────────────────────────
    // Every function below builds a *new* object or array and assigns it. QML
    // only emits change signals when a property is reassigned, so mutating
    // `layout` or `hidden` in place would leave the bar showing the old order.

    // Turn whatever was stored — or nothing at all — into a complete layout.
    // Unknown and duplicate ids disappear, and every known pill the stored value
    // does not mention lands in its default group. `legacyTernSide` is the old
    // single-pill setting, read once so an upgrade keeps the Tern pill where it
    // was; pass "" when the stored value already has a layout.
    function normalize(raw, legacyTernSide) {
        const seen = [];
        const out = { left: [], center: [], right: [] };
        const stored = (raw && typeof raw === "object") ? raw : null;

        for (let s = 0; s < root.sides.length; s++) {
            const side = root.sides[s];
            const list = (stored && Array.isArray(stored[side])) ? stored[side] : [];
            for (let i = 0; i < list.length; i++) {
                const id = list[i];
                if (root.pillIds.indexOf(id) !== -1 && seen.indexOf(id) === -1) {
                    seen.push(id);
                    out[side].push(id);
                }
            }
        }

        for (let d = 0; d < root.sides.length; d++) {
            const defSide = root.sides[d];
            const defs = root.defaultLayout[defSide];
            for (let j = 0; j < defs.length; j++) {
                const id = defs[j];
                if (seen.indexOf(id) !== -1)
                    continue;
                seen.push(id);
                const legacy = (id === "tern" && !stored && root.sides.indexOf(legacyTernSide) !== -1);
                out[legacy ? legacyTernSide : defSide].push(id);
            }
        }
        return out;
    }

    // Which group a pill currently sits in, or "" if it is in none.
    function sideOf(id) {
        for (let s = 0; s < root.sides.length; s++) {
            const side = root.sides[s];
            if ((root.layout[side] || []).indexOf(id) !== -1)
                return side;
        }
        return "";
    }

    function isHidden(id) {
        return root.hidden.indexOf(id) !== -1;
    }

    // Show or hide one pill in place; its slot in the layout is kept.
    function setHidden(id, hide) {
        if (root.pillIds.indexOf(id) === -1)
            return;
        const want = !!hide;
        if (root.isHidden(id) === want)
            return;
        const next = root.hidden.filter(function (x) { return x !== id; });
        if (want)
            next.push(id);
        root.hidden = next;
        root.save();
    }

    // Move a pill to `index` inside `side`. `index` is the slot the drop was
    // aimed at, counted before the pill is taken out of the list it came from.
    function movePill(id, side, index) {
        if (root.pillIds.indexOf(id) === -1 || root.sides.indexOf(side) === -1)
            return;

        const next = {
            left: (root.layout.left || []).slice(),
            center: (root.layout.center || []).slice(),
            right: (root.layout.right || []).slice()
        };

        const oldSide = root.sideOf(id);
        const oldIndex = oldSide === "" ? -1 : next[oldSide].indexOf(id);
        if (oldIndex !== -1)
            next[oldSide].splice(oldIndex, 1);
        // Pulling a pill out of the same list shifts every slot after it up by
        // one, so a drop further down names a slot that no longer exists.
        if (oldSide === side && oldIndex !== -1 && index > oldIndex)
            index -= 1;

        const target = next[side];
        target.splice(Math.max(0, Math.min(index, target.length)), 0, id);

        if (JSON.stringify(next) === JSON.stringify(root.layout))
            return;
        root.layout = next;
        root.save();
    }

    // The Tern pill's right-click: on to the next group, wrapping around.
    function cycleTernPillSide() {
        const i = root.sides.indexOf(root.sideOf("tern"));
        const next = root.sides[(i + 1) % root.sides.length];
        root.movePill("tern", next, (root.layout[next] || []).length);
    }

    function resetLayout() {
        root.layout = root.normalize(root.defaultLayout, "");
        root.hidden = [];
        root.save();
    }

    function save() {
        file.setText(JSON.stringify({ layout: root.layout, hidden: root.hidden }, null, 2) + "\n");
    }

    // ── Settings page ──────────────────────────────────────────────────────

    // Open the page on `tab` — "layout" or "wallpaper". Anything else falls
    // back to the layout editor.
    function openSettings(tab) {
        root.settingsTab = (tab === "wallpaper") ? "wallpaper" : "layout";
        root.settingsOpen = true;
    }

    // Mod+B, Mod+W, the gear and the wallpaper button: close when the page is
    // already showing `tab`, otherwise switch to it. So pressing Mod+W twice
    // opens and then closes, rather than re-opening.
    function toggleSettings(tab) {
        if (root.settingsOpen && root.settingsTab === tab) {
            root.settingsOpen = false;
        } else {
            root.openSettings(tab);
        }
    }

    // Where things live. Everything is derived from $HOME or from this repo, so
    // the bar works for any user. Change these if your setup differs.
    readonly property string home: String(Quickshell.env("HOME") || "")
    readonly property string scriptsDir: Quickshell.shellDir + "/scripts"
    readonly property string configPath: Quickshell.shellDir + "/bar.json"
    readonly property string ternBin: root.home + "/.local/bin/tern"
    readonly property string pokeDataDir: root.home + "/.local/state/tern/plugin-data/poke"
    // The wallpaper page's backend: the settings file it alone writes, the two
    // scripts it runs, and the preset themes it lists.
    readonly property string wallpaperStatePath: root.home + "/.config/niri/wallpaper.json"
    readonly property string wallpaperScript: root.home + "/.config/niri/scripts/wallpaper.sh"
    readonly property string themeSyncScript: root.home + "/.config/niri/scripts/theme-sync.sh"
    readonly property string themePresetsPath: root.home + "/.config/matugen/presets.json"
    // Optional: a script that shows your keybindings. The bar does nothing if it is missing.
    readonly property string cheatsheetScript: root.home + "/.config/niri/scripts/cheatsheet.sh"

    FileView {
        id: file
        path: root.configPath
        printErrors: false

        // A missing or broken file just leaves the defaults in place.
        onLoaded: {
            try {
                const o = JSON.parse(file.text());
                // Hidden first, so the layout change that follows already knows
                // which pills to leave out.
                root.hidden = (Array.isArray(o.hidden) ? o.hidden : [])
                    .filter((id, i, a) => root.pillIds.indexOf(id) !== -1 && a.indexOf(id) === i);
                root.layout = root.normalize(o.layout, o.ternPillSide);
            } catch (e) {
            }
        }
    }
}
