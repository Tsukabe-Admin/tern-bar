import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "../singletons/looks.js"), "utf8").replace(/^\s*\.pragma\s+library\s*\n/, "");
const mod = new Function(
    src + "\nreturn { LOOKS, DEFAULT_LOOK, FRAME_DEPTHS, FRAME_DEPTH_SPECS, DEFAULT_LOOK_OPTIONS, normalizeLook, nextLook, normalizeFrameDepth, frameDepthSpec, normalizeLookOptions, relativeLuminance, contrastRatio, contrastInk, clampDrawerX, detectNiriFullscreenOutputs };"
)();

test("normalizeLook defaults invalid inputs to pills and accepts frame", () => {
    assert.equal(mod.DEFAULT_LOOK, "pills");
    assert.equal(mod.normalizeLook(undefined), "pills");
    assert.equal(mod.normalizeLook(null), "pills");
    assert.equal(mod.normalizeLook(""), "pills");
    assert.equal(mod.normalizeLook("unknown"), "pills");
    assert.equal(mod.normalizeLook(42), "pills");
    assert.equal(mod.normalizeLook("pills"), "pills");
    assert.equal(mod.normalizeLook("frame"), "frame");
    assert.equal(mod.normalizeLook(" FRAME "), "frame");
});

test("nextLook cycles deterministically across LOOKS", () => {
    assert.equal(mod.nextLook("pills"), "frame");
    assert.equal(mod.nextLook("frame"), "pills");
    assert.equal(mod.nextLook("bogus"), "frame");
    assert.equal(mod.nextLook(null), "frame");
});

test("normalizeFrameDepth and frameDepthSpec validate off, subtle, medium and fallback cleanly", () => {
    assert.deepEqual(mod.FRAME_DEPTHS, ["off", "subtle", "medium"]);
    assert.equal(mod.normalizeFrameDepth(undefined), "subtle");
    assert.equal(mod.normalizeFrameDepth(null), "subtle");
    assert.equal(mod.normalizeFrameDepth(""), "subtle");
    assert.equal(mod.normalizeFrameDepth("heavy"), "subtle");
    assert.equal(mod.normalizeFrameDepth(123), "subtle");
    assert.equal(mod.normalizeFrameDepth(" OFF "), "off");
    assert.equal(mod.normalizeFrameDepth("Subtle"), "subtle");
    assert.equal(mod.normalizeFrameDepth("medium"), "medium");

    const off = mod.frameDepthSpec("off");
    const subtle = mod.frameDepthSpec("subtle");
    const medium = mod.frameDepthSpec("medium");
    assert.equal(off.id, "off");
    assert.equal(off.extent, 0);
    assert.equal(off.keyOpacity, 0);
    assert.equal(off.aoOpacity, 0);

    assert.equal(subtle.id, "subtle");
    assert.ok(subtle.extent > 0);
    assert.ok(subtle.keyOpacity > 0);
    assert.ok(subtle.aoOpacity > 0);

    assert.equal(medium.id, "medium");
    assert.ok(medium.extent > subtle.extent);
    assert.ok(medium.keyOpacity > subtle.keyOpacity);
    assert.ok(medium.aoOpacity > subtle.aoOpacity);

    // The shaders read every field: a missing one would reach them as undefined.
    for (const spec of [off, subtle, medium]) {
        for (const field of ["keyOpacity", "aoOpacity", "sigma", "aoSigma", "offsetY", "extent"])
            assert.equal(typeof spec[field], "number", `${spec.id}.${field}`);
    }
    // The wide key shadow is softer than the tight contact shadow, and it falls downwards.
    assert.ok(subtle.sigma > subtle.aoSigma);
    assert.ok(medium.sigma > medium.aoSigma);
    assert.ok(subtle.offsetY > 0);
    assert.equal(off.sigma, 0);

    // Returns an isolated copy
    subtle.extent = 999;
    assert.notEqual(mod.frameDepthSpec("subtle").extent, 999);
});

test("normalizeLookOptions clamps numeric bounds and falls back invalid enums", () => {
    assert.deepEqual(mod.normalizeLookOptions(undefined), {
        frameThickness: 8,
        innerRounding: 18,
        surfaceFinish: "translucent",
        motionProfile: "expressive",
        frameDepth: "subtle"
    });

    assert.deepEqual(mod.normalizeLookOptions({
        frameThickness: 1,
        innerRounding: 99,
        surfaceFinish: "solid",
        motionProfile: "calm",
        frameDepth: "medium"
    }), {
        frameThickness: 4,
        innerRounding: 28,
        surfaceFinish: "solid",
        motionProfile: "calm",
        frameDepth: "medium"
    });

    assert.deepEqual(mod.normalizeLookOptions({
        frameThickness: 100,
        innerRounding: -5,
        surfaceFinish: "glass",
        motionProfile: "turbo",
        frameDepth: "extreme"
    }), {
        frameThickness: 14,
        innerRounding: 8,
        surfaceFinish: "translucent",
        motionProfile: "expressive",
        frameDepth: "subtle"
    });

    assert.deepEqual(mod.normalizeLookOptions({
        frameThickness: true,
        innerRounding: NaN,
        frameDepth: " OFF "
    }), {
        frameThickness: 8,
        innerRounding: 18,
        surfaceFinish: "translucent",
        motionProfile: "expressive",
        frameDepth: "off"
    });
});

test("normalizeLookOptions drops keys it does not know and tolerates hand-edited values", () => {
    // An option an older version wrote (cornerStyle) is not carried along.
    assert.deepEqual(Object.keys(mod.normalizeLookOptions({ cornerStyle: "arc", frameThickness: 9 })).sort(),
        ["frameDepth", "frameThickness", "innerRounding", "motionProfile", "surfaceFinish"]);

    // Not a number at all: the default, not the minimum.
    for (const junk of ["", "  ", null, [10], {}, "wide"]) {
        assert.equal(mod.normalizeLookOptions({ frameThickness: junk }).frameThickness, 8, JSON.stringify(junk));
        assert.equal(mod.normalizeLookOptions({ innerRounding: junk }).innerRounding, 18, JSON.stringify(junk));
    }
    // A number written as text or with a fraction is used, rounded.
    assert.equal(mod.normalizeLookOptions({ frameThickness: "10" }).frameThickness, 10);
    assert.equal(mod.normalizeLookOptions({ frameThickness: 9.6 }).frameThickness, 10);
    assert.equal(mod.normalizeLookOptions({ innerRounding: 12.4 }).innerRounding, 12);

    // Words are matched whatever their case and surrounding spaces.
    assert.equal(mod.normalizeLookOptions({ surfaceFinish: " Solid " }).surfaceFinish, "solid");
    assert.equal(mod.normalizeLookOptions({ motionProfile: "CALM\n" }).motionProfile, "calm");
    assert.equal(mod.normalizeLook(["frame"]), "pills");
    assert.equal(mod.normalizeFrameDepth(["off"]), "subtle");
});

test("contrastInk picks high-contrast foreground for light and dark accent hexes and QML color objects", () => {
    assert.equal(mod.contrastInk("#ffffff", "#101010", "#f4f4f4"), "#101010");
    assert.equal(mod.contrastInk("#0d0f14", "#101010", "#f4f4f4"), "#f4f4f4");
    assert.equal(mod.contrastInk("#ffe066", "#18181b", "#fafafa"), "#18181b");
    assert.equal(mod.contrastInk("#ff000080"), "#f5f5f5"); // Qt's #AARRGGBB: alpha ff, then dark navy -> light ink
    assert.equal(mod.contrastInk("#fffff0c0", "#111111", "#f5f5f5"), "#111111"); // #AARRGGBB light cream -> dark ink
    assert.equal(mod.contrastInk({ r: 0.9, g: 0.92, b: 0.95, a: 1 }, "#121212", "#f0f0f0"), "#121212");
    assert.equal(mod.contrastInk({ r: 0.12, g: 0.14, b: 0.2, a: 1 }, "#121212", "#f0f0f0"), "#f0f0f0");
    assert.equal(mod.contrastInk("#fff"), "#111111"); // #RGB, and the default dark ink
    assert.equal(mod.contrastInk("not a colour"), "#f5f5f5"); // unreadable counts as black
});

test("luminance and contrast follow the WCAG 2 formula", () => {
    const near = (actual, expected, tolerance, label) =>
        assert.ok(Math.abs(actual - expected) <= tolerance, `${label}: ${actual} is not ${expected}`);

    // The three channel weights.
    near(mod.relativeLuminance("#ff0000"), 0.2126, 1e-4, "red");
    near(mod.relativeLuminance("#00ff00"), 0.7152, 1e-4, "green");
    near(mod.relativeLuminance("#0000ff"), 0.0722, 1e-4, "blue");
    // The gamma curve: mid grey is far darker than half.
    near(mod.relativeLuminance("#808080"), 0.2159, 1e-3, "mid grey");
    // Below the threshold the curve is a straight line.
    near(mod.relativeLuminance("#0a0a0a"), 0.0030, 2e-4, "near black");
    // Published reference ratios: black on white, and the grey that just misses 4.5:1.
    near(mod.contrastRatio("#000000", "#ffffff"), 21, 1e-9, "black on white");
    near(mod.contrastRatio("#ffffff", "#777777"), 4.48, 0.01, "#777 on white");
    // A colour object's channels are clamped to 0..1.
    near(mod.relativeLuminance({ r: 2, g: 2, b: 2 }), 1, 1e-9, "over-range object");
});

test("clampDrawerX centers on anchor and clamps within inner frame bounds", () => {
    // Normal centered
    assert.equal(mod.clampDrawerX(500, 300, 100, 1800), 350);
    // Clamped left
    assert.equal(mod.clampDrawerX(120, 300, 100, 1800), 100);
    // Clamped right
    assert.equal(mod.clampDrawerX(1750, 300, 100, 1800), 1500);
    // Drawer wider than span clamps to minX, wherever the anchor is
    assert.equal(mod.clampDrawerX(500, 900, 100, 600), 100);
    assert.equal(mod.clampDrawerX(600, 900, 100, 600), 100);
    // Whole pixels
    assert.equal(mod.clampDrawerX(500.4, 301, 100, 1800), 350);
});

test("detectNiriFullscreenOutputs distinguishes active fullscreen windows from maximized and inactive workspaces", () => {
    const screens = {
        "DP-1": { width: 2560, height: 1440 },
        "DP-2": { width: 3440, height: 1440 }
    };
    const workspaces = (activeOnDp1, activeOnDp2) => [
        { id: 4, output: "DP-1", is_active: true, active_window_id: activeOnDp1 },
        { id: 5, output: "DP-1", is_active: false, active_window_id: 10 },
        { id: 8, output: "DP-2", is_active: true, active_window_id: activeOnDp2 }
    ];

    // Exclusive-zone maximized window ([2536, 1368]) is NOT fullscreen; the fullscreen window on DP-1's
    // inactive workspace is ignored
    assert.deepEqual(mod.detectNiriFullscreenOutputs([
        { id: 9, workspace_id: 4, layout: { tile_size: [2536, 1368] } },
        { id: 10, workspace_id: 5, layout: { tile_size: [2560, 1440] } },
        { id: 11, workspace_id: 8, layout: { tile_size: [1702, 1368] } }
    ], workspaces(9, 11), screens), { "DP-1": false, "DP-2": false });

    // Fractional-scale rounded fullscreen window on DP-1 active workspace -> DP-1 true, DP-2 false
    assert.deepEqual(mod.detectNiriFullscreenOutputs([
        { id: 9, workspace_id: 4, layout: { tile_size: [2559.4, 1439.6] } },
        { id: 11, workspace_id: 8, layout: { tile_size: [3440, 1368] } }
    ], workspaces(9, 11), screens), { "DP-1": true, "DP-2": false });

    // ...but three pixels short is an ordinary window
    assert.deepEqual(mod.detectNiriFullscreenOutputs([
        { id: 9, workspace_id: 4, layout: { tile_size: [2557, 1440] } }
    ], workspaces(9, null), screens), { "DP-1": false, "DP-2": false });

    // window_size fallback & invalid/null layouts remain safe
    assert.deepEqual(mod.detectNiriFullscreenOutputs([
        null,
        { id: 12, workspace_id: 8, layout: { window_size: [3440, 1440] } },
        { id: 13, workspace_id: 4, layout: { tile_size: [NaN, 1440] } }
    ], workspaces(13, 12), screens), { "DP-1": false, "DP-2": true });

    // tile_size wins over window_size (a fullscreen tile around a smaller client)
    assert.deepEqual(mod.detectNiriFullscreenOutputs([
        { id: 9, workspace_id: 4, layout: { tile_size: [2560, 1440], window_size: [1280, 720] } }
    ], workspaces(9, null), screens), { "DP-1": true, "DP-2": false });
});

test("detectNiriFullscreenOutputs follows the window in front, not any screen-sized window", () => {
    const screens = { "DP-1": { width: 2560, height: 1440 } };
    const windows = [
        { id: 13, workspace_id: 1, layout: { tile_size: [2560, 1440] } },
        { id: 14, workspace_id: 1, layout: { tile_size: [1254, 1370] } }
    ];
    const ws = (active) => [{ id: 1, output: "DP-1", is_active: true, active_window_id: active }];

    // The fullscreen window is the one in front, whatever its place in the list.
    assert.deepEqual(mod.detectNiriFullscreenOutputs(windows, ws(13), screens), { "DP-1": true });
    assert.deepEqual(mod.detectNiriFullscreenOutputs(windows.slice().reverse(), ws(13), screens), { "DP-1": true });
    // The view scrolled to the column beside it: the fullscreen window keeps its size, the bar is back.
    assert.deepEqual(mod.detectNiriFullscreenOutputs(windows, ws(14), screens), { "DP-1": false });
    // A floating window the size of the screen does not hide the bar.
    assert.deepEqual(mod.detectNiriFullscreenOutputs([
        { id: 15, workspace_id: 1, is_floating: true, layout: { tile_size: [2560, 1440] } }
    ], ws(15), screens), { "DP-1": false });
    // Nothing known about the screens or the workspaces: nothing is fullscreen.
    assert.deepEqual(mod.detectNiriFullscreenOutputs(windows, ws(13), null), { "DP-1": false });
    assert.deepEqual(mod.detectNiriFullscreenOutputs(windows, null, screens), { "DP-1": false });
    assert.deepEqual(mod.detectNiriFullscreenOutputs(null, ws(13), screens), { "DP-1": false });
});

test("normalizeLookOptions(null) yields an isolated defaults object matching Reset Frame", () => {
    const a = mod.normalizeLookOptions(null);
    const b = mod.normalizeLookOptions(undefined);
    assert.deepEqual(a, mod.DEFAULT_LOOK_OPTIONS);
    assert.deepEqual(b, mod.DEFAULT_LOOK_OPTIONS);
    a.frameThickness = 14;
    assert.equal(mod.normalizeLookOptions(null).frameThickness, 8);
});
