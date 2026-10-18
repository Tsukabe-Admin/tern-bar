pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Bar preferences, persisted to ~/.config/tern-bar/bar.json: the order of the pills in the
// bar's three groups ("left", "center", "right") and which of them are hidden.
// Edit it from the settings page — the gear in the tools pill, a right-click on
// the launcher, or Mod+B — or by hand, then restart the bar (the file is read
// once at start).
Singleton {
    id: root

    // The three groups, left to right on screen.
    readonly property var sides: ["left", "center", "right"]

    // Every pill the bar has. A pill is known here under the same id it uses in
    // BarPanel.pills; anything else in bar.json is ignored.
    readonly property var pillIds: ["launcher", "workspaces", "title", "clock", "weather", "media",
        "poke", "updates", "resources", "network", "volume", "mic", "keyboard", "battery", "tray",
        "tools", "system", "tern"]

    // Display names for the settings page.
    readonly property var pillNames: ({
        launcher: "Launcher", workspaces: "Workspaces", title: "Window title", clock: "Clock",
        weather: "Weather", media: "Media", poke: "PokeToken", updates: "System updates",
        resources: "CPU & memory", network: "Network", volume: "Volume", mic: "Microphone",
        keyboard: "Keyboard layout", battery: "Battery", tray: "System tray", tools: "Tools",
        system: "Quick settings, notifications & power", tern: "Tern"
    })

    // The order the bar ships with — also what "Reset layout" restores. A pill
    // added to the bar in future lands in the group it appears in here.
    readonly property var defaultLayout: ({
        left: ["launcher", "workspaces", "title"],
        center: ["clock", "weather", "media"],
        right: ["poke", "updates", "resources", "network", "volume", "mic", "keyboard", "battery",
            "tray", "tools", "system", "tern"]
    })

    // Current layout: { left: [pillId], center: [pillId], right: [pillId] }.
    property var layout: root.normalize(null, "")
    // Pills that keep their slot in the layout but are not shown on the bar.
    property var hidden: []
    // True once bar.json has been read — or its absence established. Pills that
    // pause their polling while hidden must wait for it: until the file lands,
    // `hidden` is the empty default and a hidden pill would poll once.
    property bool configLoaded: false
    // Night light on/off (singletons/NightLight.qml), kept across restarts.
    property bool nightLight: false
    // Weather in Fahrenheit instead of Celsius; toggled from the forecast popup.
    property bool weatherFahrenheit: false
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
                const targetSide = legacy ? legacyTernSide : defSide;
                const targetList = out[targetSide];
                let insertPos = -1;
                if (!legacy) {
                    for (let k = j + 1; k < defs.length; k++) {
                        const pos = targetList.indexOf(defs[k]);
                        if (pos !== -1) {
                            insertPos = pos;
                            break;
                        }
                    }
                }
                if (insertPos !== -1)
                    targetList.splice(insertPos, 0, id);
                else
                    targetList.push(id);
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

    function setNightLight(on) {
        if (root.nightLight === !!on)
            return;
        root.nightLight = !!on;
        root.save();
    }

    function setWeatherFahrenheit(on) {
        if (root.weatherFahrenheit === !!on)
            return;
        root.weatherFahrenheit = !!on;
        root.save();
    }

    function save() {
        file.setText(JSON.stringify({
            layout: root.layout,
            hidden: root.hidden,
            nightLight: root.nightLight,
            weatherFahrenheit: root.weatherFahrenheit
        }, null, 2) + "\n");
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

    // Where things live. Your settings go in $XDG_CONFIG_HOME/tern-bar
    // (~/.config/tern-bar), files the bar generates in $XDG_STATE_HOME/tern-bar
    // (~/.local/state/tern-bar), and everything else ships in this repo — so the
    // bar works for anyone who clones it, and `git pull` never touches your
    // settings. scripts/*.sh compute the same two folders the same way.
    readonly property string home: String(Quickshell.env("HOME") || "")
    readonly property string configDir:
        (String(Quickshell.env("XDG_CONFIG_HOME") || "") || (root.home + "/.config")) + "/tern-bar"
    readonly property string stateDir:
        (String(Quickshell.env("XDG_STATE_HOME") || "") || (root.home + "/.local/state")) + "/tern-bar"
    readonly property string scriptsDir: Quickshell.shellDir + "/scripts"
    readonly property string configPath: root.configDir + "/bar.json"
    // The Wallpaper tab: the settings file it alone writes, the palette
    // scripts/theme-sync.sh generates, and the preset themes it lists.
    readonly property string wallpaperStatePath: root.configDir + "/wallpaper.json"
    readonly property string palettePath: root.stateDir + "/palette.json"
    readonly property string themePresetsPath: Quickshell.shellDir + "/themes/presets.json"
    // The PokeToken plugin's data, where the Tern app keeps it.
    readonly property string pokeDataDir: root.home + "/.local/state/tern/plugin-data/poke"

    function loadFromText(rawText) {
        try {
            const o = JSON.parse(rawText);
            if (o && typeof o === "object") {
                root.hidden = (Array.isArray(o.hidden) ? o.hidden : [])
                    .filter((id, i, a) => root.pillIds.indexOf(id) !== -1 && a.indexOf(id) === i);
                root.layout = root.normalize(o.layout, o.ternPillSide);
                root.nightLight = o.nightLight === true;
                root.weatherFahrenheit = o.weatherFahrenheit === true;
            }
        } catch (e) {
        }
        root.configLoaded = true;
    }

    FileView {
        id: file
        path: root.configPath
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: root.loadFromText(file.text())
}
