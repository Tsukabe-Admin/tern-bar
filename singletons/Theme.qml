pragma Singleton

import QtQuick

// Palette of the ACTIVE Tern theme. Tern's settings.json says
// {"theme": "Dark", "theme_dark": "dark-midnight"}, so every color below is
// the dark-midnight entry of Tern's theme registry (src/themes.rs), dumped
// from the binary:
//   export:   pageBg #000000, cardBg #050f16, infoBg #001008
//   terminal: background/chrome #000000 (userMsgBg), widget #050f16
//   colors:   accent/border #2979ff, borderMuted #263238, muted #b0bec5,
//             dim #546e7a, success #00e676, warning #ffea00, error #ff1744
//   vars:     cyan #00e5ff, link/mdLink #40c4ff
// Tern's default appearance is a "Clear" material (60% opacity, 56px blur —
// from `tern ctl state`), so the capsules stay translucent with a backdrop
// blur request instead of going flat.
//
// To retheme, either edit the values or re-dump the active theme:
//   strings ~/.omp/tern/tern | awk '/"name": "dark-midnight"/{f=1} f&&n++<90'
QtObject {
    // Surfaces (Tern page, terminal chrome, raised card stock)
    readonly property color page: "#000000"
    readonly property color panel: "#000000"
    readonly property color card: "#050F16"
    readonly property color raise: "#080810"

    // Launch morph: the terminal's own black at the bar's translucency, so the
    // growing shape reads as a capsule of the same material as the bar and
    // dissolves into the real window.
    readonly property color morphFill: "#DB000000"

    // Capsule fill: the theme's raised surface at Tern's --pop-bg alpha (98%).
    // 92% so the requested backdrop blur keeps a hint of the wallpaper.
    readonly property color popBg: "#EB050F16"

    // Hairlines / tints. rim is ink 9% PRE-computed over #050f16 (instead of
    // alpha) so the 1px line stays a neutral grey — a translucent border picks
    // up the wallpaper through the antialiased edge and reads as a teal tint.
    readonly property color rim: "#1A2329"
    readonly property color glassHi: "#07FFFFFF"  // --sf-card-bg, white 2.8%
    readonly property color hover: "#0FEDEDED"    // --l1, ink 6%
    readonly property color l3: "#24EDEDED"       // ink 14%
    readonly property color l4: "#38EDEDED"       // ink 22%

    // Type (ink + the theme's grays)
    readonly property color t1: "#EDEDED"  // --ink
    readonly property color t2: "#B0BEC5"  // theme "gray" (muted)
    readonly property color t3: "#546E7A"  // theme "dimGray" (dim)
    readonly property color t4: "#263238"  // theme "darkGray" (borderMuted)

    // Accents
    readonly property color accent: "#2979FF"     // theme accent / border
    readonly property color accentInk: "#40C4FF"  // theme link
    readonly property color live: "#00E5FF"       // theme cyan
    readonly property color ok: "#00E676"         // theme success
    readonly property color warn: "#FFEA00"       // theme warning
    readonly property color bad: "#FF1744"        // theme error

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

    // Type
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 13
}
