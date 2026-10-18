pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Colors follow the wallpaper or a preset theme. scripts/theme-sync.sh (run by
// the Wallpaper tab) writes ~/.local/state/tern-bar/palette.json; this
// singleton watches that file and crossfades to the new colors. With no
// palette file yet the bar keeps the fallbacks below, which are the
// dark-midnight entry of Tern's theme registry (src/themes.rs):
//   card #050F16, ink #EDEDED, muted #B0BEC5, dim #546E7A, darkGray #263238,
//   accent #2979FF, cyan #00E5FF, error #FF1744.
// Setup and the token mapping: README, "Wallpaper and colors".
Singleton {
    id: root

    readonly property string palettePath: BarConfig.palettePath

    // Parsed palette; {} when the file is missing or not valid JSON.
    readonly property var palette: {
        try {
            const o = JSON.parse(paletteFile.text());
            return (o && typeof o === "object") ? o : {};
        } catch (e) {
            return {};
        }
    }

    function pick(key, fallback) {
        const v = root.palette[key];
        return (typeof v === "string" && /^#[0-9a-fA-F]{6}$/.test(v)) ? v : fallback;
    }

    FileView {
        id: paletteFile
        path: root.palettePath
        blockLoading: true      // first frame already has the right colors
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    // theme-sync.sh just wrote a new palette. Toggling watchChanges rebuilds
    // the file watcher, then the file is read at once. Needed on a fresh
    // install: ~/.local/state/tern-bar did not exist when the bar started, so
    // the watcher had no folder to watch and would never see the first palette.
    function reloadPalette() {
        paletteFile.watchChanges = false;
        paletteFile.watchChanges = true;
        paletteFile.reload();
    }

    // ── Base colors (from the palette; animated so a wallpaper change fades) ──
    property color card: root.pick("card", "#050F16")
    property color t1: root.pick("ink", "#EDEDED")      // ink
    property color t2: root.pick("muted", "#B0BEC5")
    property color t3: root.pick("dim", "#546E7A")
    property color t4: root.pick("faint", "#263238")
    property color accent: root.pick("accent", "#2979FF")
    property color live: root.pick("live", "#00E5FF")
    property color bad: root.pick("bad", "#FF1744")

    // Status colors keep their meaning whatever the wallpaper is.
    readonly property color ok: "#00E676"
    readonly property color warn: "#FFEA00"

    Behavior on card { ColorAnimation { duration: root.paletteFade } }
    Behavior on t1 { ColorAnimation { duration: root.paletteFade } }
    Behavior on t2 { ColorAnimation { duration: root.paletteFade } }
    Behavior on t3 { ColorAnimation { duration: root.paletteFade } }
    Behavior on t4 { ColorAnimation { duration: root.paletteFade } }
    Behavior on accent { ColorAnimation { duration: root.paletteFade } }
    Behavior on live { ColorAnimation { duration: root.paletteFade } }
    Behavior on bad { ColorAnimation { duration: root.paletteFade } }

    // ── Derived surfaces (Tern's ink-alpha convention) ──
    // Capsule fill: the card at Tern's --pop-bg alpha, 92% so the requested
    // backdrop blur keeps a hint of the wallpaper.
    readonly property color popBg: Qt.alpha(root.card, 0.92)
    // Hairline: ink 9% PRE-computed over the card (instead of a translucent
    // border) so the 1px line stays neutral — a translucent border picks up the
    // wallpaper through the antialiased edge and reads as a tint.
    readonly property color rim: Qt.tint(root.card, Qt.alpha(root.t1, 0.09))
    readonly property color hover: Qt.alpha(root.t1, 0.06)   // --l1
    readonly property color l3: Qt.alpha(root.t1, 0.14)

    // Launch morph: the terminal's own black at the bar's translucency, so the
    // growing shape reads as a capsule of the same material as the bar and
    // dissolves into the real window. Fixed: it matches the terminal, not the bar.
    readonly property color morphFill: "#DB000000"

    // Bar geometry (40px surface, 8px top margin; Quickshell adds the margin
    // to exclusiveZone, so 40 + 8 = 48 reserved — identical to waybar's)
    readonly property int barHeight: 40
    readonly property int barMarginTop: 8
    readonly property int barMarginSide: 12
    readonly property int exclusiveZone: 40
    readonly property int radiusCard: 12  // Tern's card radius

    // Capsules ("pills") — the bar is a row of these
    readonly property int pillHeight: 32
    readonly property int pillRadius: 16  // stadium: half the pill height
    readonly property int pillSpacing: 6
    // A row with this many visible capsules merges into one continuous island
    // (the individual fills fade out and the gaps close). Raise it to keep
    // capsules separate, or lower it to merge sooner.
    readonly property int pillMergeThreshold: 4
    readonly property int pillPadding: 3       // vertical inset (items stay 26px tall)
    readonly property int pillPaddingSide: 6   // horizontal breathing room inside a capsule
    readonly property int itemRadius: 10
    // Breathing room between the outermost capsules and the bar's screen edge
    // (on top of barMarginSide, so the outer pill sits 18px from the screen).
    readonly property int barPadding: 6

    // Launch morph: mirrors of niri's geometry (config.kdl: gaps 12; the bar
    // reserves 48 from the top) used to aim the morph at the tile a new
    // terminal lands in.
    readonly property int workAreaTop: 48
    readonly property int workAreaGap: 12

    // Motion (ms)
    readonly property int motionFast: 140
    readonly property int motionBase: 220
    readonly property int motionSlow: 340
    readonly property int paletteFade: 600  // wallpaper change crossfade

    // Type
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 13
}
