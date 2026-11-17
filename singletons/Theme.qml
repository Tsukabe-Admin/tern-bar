pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "looks.js" as LooksLib

// Colors follow the wallpaper or a preset theme. scripts/theme-sync.sh (run by
// the Wallpaper tab) writes ~/.local/state/skua/palette.json; this
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
    // install: ~/.local/state/skua did not exist when the bar started, so
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

    // ── The active Look's tokens (see Looks.qml) ──
    readonly property bool isFramed: Looks.isFramed
    readonly property int frameThickness: Looks.frameThickness
    readonly property int innerRounding: Looks.innerRounding
    readonly property int wingRadius: Looks.wingRadius
    readonly property bool frameShadowEnabled: Looks.frameShadowEnabled
    readonly property real frameShadowKeyOpacity: Looks.frameDepthSpec.keyOpacity
    readonly property real frameShadowAoOpacity: Looks.frameDepthSpec.aoOpacity
    readonly property real frameShadowSigma: Looks.frameDepthSpec.sigma
    readonly property real frameShadowAoSigma: Looks.frameDepthSpec.aoSigma
    readonly property real frameShadowOffsetY: Looks.frameDepthSpec.offsetY
    readonly property int frameShadowExtent: Looks.frameDepthSpec.extent
    readonly property var curveSpatial: Looks.curveSpatial
    readonly property var curveSpatialFast: Looks.curveSpatialFast
    readonly property var curveEffects: Looks.curveEffects

    // ── Derived surfaces (Tern's ink-alpha convention) ──
    // Ink for a label on top of Theme.accent (today's date, the play button,
    // the active workspace chip): the card colour, as it has always been,
    // unless the accent is too dark for it; then a light ink.
    // (Not named "onAccent": QML reads a name that starts with "on" and a
    // capital letter as a signal handler. The property existed, its
    // calculation never ran, and the ink was always black.)
    readonly property color accentInk: LooksLib.contrastInk(root.accent, root.card, "#f5f7fa")

    // Capsule / frame fill: the card at Tern's --pop-bg alpha (92%, so the
    // requested backdrop blur keeps a hint of the wallpaper), or solid ink
    // with the Frame look's Solid finish.
    readonly property color popBg: Qt.alpha(root.card, Looks.activeSpec.frameAlpha)
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

    // Bar geometry — delegated to active Look spec ("pills" keeps original pixels)
    readonly property int barHeight: Looks.activeSpec.barHeight
    readonly property int barMarginTop: Looks.activeSpec.barMarginTop
    readonly property int barMarginSide: Looks.activeSpec.barMarginSide
    readonly property int exclusiveZone: Looks.activeSpec.exclusiveZone
    readonly property int radiusCard: Looks.activeSpec.radiusCard

    // Capsules ("pills")
    readonly property int pillHeight: Looks.activeSpec.pillHeight
    readonly property int pillRadius: Looks.activeSpec.pillRadius
    readonly property int pillSpacing: Looks.activeSpec.pillSpacing
    readonly property int pillMergeThreshold: Looks.activeSpec.pillMergeThreshold
    readonly property int pillPadding: Looks.activeSpec.pillPadding
    readonly property int pillPaddingSide: Looks.activeSpec.pillPaddingSide
    readonly property int itemRadius: Looks.activeSpec.itemRadius
    readonly property int barPadding: Looks.activeSpec.barPadding

    // Launch morph: mirrors of niri's geometry (config.kdl: gaps 12; the bar
    // reserves workAreaTop from the top, and the Frame look its thickness on the
    // other three edges) used to aim the morph at the tile a new terminal lands in.
    readonly property int workAreaTop: Looks.activeSpec.workAreaTop
    readonly property int workAreaGap: 12

    // Motion (ms)
    readonly property int motionFast: Looks.durationFast
    readonly property int motionBase: Looks.durationBase
    readonly property int motionSlow: Looks.durationSlow
    readonly property int paletteFade: 600  // wallpaper change crossfade

    // Type
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 13
}
