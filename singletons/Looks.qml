pragma Singleton

import QtQuick
import Quickshell
import "looks.js" as LooksLib

// Active bar Look ("pills" or "frame") and its live design tokens.
// BarConfig holds the persisted choice and restyling guard; this singleton
// derives layout, surface, corner, and motion tokens without circular deps.
Singleton {
    id: root

    // Every Look, in the order the Look tab shows them, and its card text.
    readonly property var available: LooksLib.LOOKS
    readonly property var metadata: LooksLib.LOOK_META

    readonly property string activeId: LooksLib.normalizeLook(BarConfig.look)
    readonly property bool isFramed: root.activeId === "frame"
    readonly property var options: LooksLib.normalizeLookOptions(BarConfig.lookOptions)
    readonly property bool restyling: BarConfig.restyling

    // The frame options are stored whichever Look is active, but they only
    // act in the Frame look: the Pills look has no control that could change them.
    readonly property int frameThickness: root.isFramed ? root.options.frameThickness : 0
    readonly property int innerRounding: root.isFramed ? root.options.innerRounding : 0
    readonly property bool solidSurface: root.isFramed && root.options.surfaceFinish === "solid"
    readonly property bool calmMotion: root.isFramed && root.options.motionProfile === "calm"
    readonly property string frameDepth: root.options.frameDepth
    readonly property bool frameShadowEnabled: root.isFramed && root.frameDepth !== "off"
    readonly property var frameDepthSpec: LooksLib.frameDepthSpec(root.isFramed ? root.frameDepth : "off")
    // Radius of the concave curve where a drawer, the launcher or the docked
    // OSD meets the frame lip. It follows the corner rounding (14 at the
    // default 18), so the junctions and the screen corners read as one shape.
    readonly property int wingRadius: root.isFramed ? Math.round(root.options.innerRounding * 7 / 9) : 0

    // Pills: a 40px surface under an 8px top margin. Quickshell adds the
    // margin to exclusiveZone, so 40 + 8 = 48 is reserved (identical to
    // waybar's). The outer pill sits barMarginSide + barPadding = 18px from
    // the screen edge.
    readonly property var _pillsSpec: ({
        barHeight: 40,
        barMarginTop: 8,
        barMarginSide: 12,
        exclusiveZone: 40,
        radiusCard: 12,         // Tern's card radius
        pillHeight: 32,
        pillRadius: 16,         // stadium: half the pill height
        pillSpacing: 6,
        // A row with this many visible capsules merges into one continuous
        // island (the individual fills fade out and the gaps close).
        pillMergeThreshold: 4,
        pillPadding: 3,         // vertical inset (items stay 26px tall)
        pillPaddingSide: 6,     // horizontal breathing room inside a capsule
        itemRadius: 10,
        barPadding: 6,
        workAreaTop: 48,
        frameAlpha: 0.92        // 92%: the requested backdrop blur keeps a hint of the wallpaper
    })

    // Frame: the bar is the frame's top lip, flush with the screen edges.
    // Pills never merge (PillRow) and nothing reads exclusiveZone (FrameHost
    // reserves each edge itself); both stay so the two specs have one shape.
    readonly property var _frameSpec: ({
        barHeight: 38,
        barMarginTop: 0,
        barMarginSide: 0,
        exclusiveZone: 38,
        radiusCard: Math.min(20, Math.max(8, root.options.innerRounding)),
        pillHeight: 30,
        pillRadius: Math.min(14, Math.max(8, root.options.innerRounding - 4)),
        pillSpacing: 4,
        pillMergeThreshold: 4,
        pillPadding: 3,
        pillPaddingSide: 6,
        itemRadius: Math.min(12, Math.max(6, Math.round(root.options.innerRounding * 0.55))),
        barPadding: Math.max(8, root.options.frameThickness + 2),
        workAreaTop: 38,
        frameAlpha: root.options.surfaceFinish === "solid" ? 1.0 : 0.92
    })

    readonly property var activeSpec: root.isFramed ? root._frameSpec : root._pillsSpec

    // Bezier curves ([x1, y1, x2, y2, 1, 1] for Qt Easing.BezierSpline).
    // "expressive" uses lively spatial overshoot for sliding capsules/drawers and
    // smooth zero-overshoot deceleration for clipped heights and fades.
    readonly property var curveSpatial: (root.isFramed && !root.calmMotion)
        ? [0.38, 1.18, 0.22, 1.0, 1, 1]
        : [0.20, 0.0, 0.0, 1.0, 1, 1]
    readonly property var curveSpatialFast: (root.isFramed && !root.calmMotion)
        ? [0.32, 1.24, 0.20, 1.0, 1, 1]
        : [0.20, 0.0, 0.0, 1.0, 1, 1]
    readonly property var curveEffects: [0.22, 1.0, 0.36, 1.0, 1, 1]

    readonly property int durationFast: 140
    readonly property int durationBase: root.isFramed ? (root.calmMotion ? 200 : 250) : 220
    readonly property int durationSlow: root.isFramed ? (root.calmMotion ? 280 : 380) : 340
}
