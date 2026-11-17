.pragma library

var LOOKS = ["pills", "frame"];
var DEFAULT_LOOK = "pills";

// The Look tab's cards read their title and summary from here.
var LOOK_META = {
    pills: {
        id: "pills",
        label: "Pills",
        summary: "Floating translucent capsule pills with independent drop-down cards."
    },
    frame: {
        id: "frame",
        label: "Frame",
        summary: "Continuous screen border lip with curved cutouts and morphing drawers."
    }
};

var FRAME_DEPTHS = ["off", "subtle", "medium"];

var FRAME_DEPTH_SPECS = {
    off: {
        id: "off",
        keyOpacity: 0.0,
        aoOpacity: 0.0,
        sigma: 0.0,
        aoSigma: 0.0,
        offsetY: 0.0,
        extent: 0
    },
    subtle: {
        id: "subtle",
        keyOpacity: 0.38,
        aoOpacity: 0.22,
        sigma: 7.0,
        aoSigma: 2.2,
        offsetY: 2.5,
        extent: 26
    },
    medium: {
        id: "medium",
        keyOpacity: 0.58,
        aoOpacity: 0.30,
        sigma: 9.5,
        aoSigma: 2.8,
        offsetY: 3.5,
        extent: 36
    }
};

var DEFAULT_LOOK_OPTIONS = {
    frameThickness: 8,
    innerRounding: 18,
    surfaceFinish: "translucent",
    motionProfile: "expressive",
    frameDepth: "subtle"
};

function normalizeLook(raw) {
    if (typeof raw !== "string") return DEFAULT_LOOK;
    var key = raw.trim().toLowerCase();
    return LOOKS.indexOf(key) !== -1 ? key : DEFAULT_LOOK;
}

function nextLook(current) {
    var cur = normalizeLook(current);
    var idx = LOOKS.indexOf(cur);
    return LOOKS[(idx + 1) % LOOKS.length];
}

function normalizeFrameDepth(raw) {
    if (typeof raw !== "string") return DEFAULT_LOOK_OPTIONS.frameDepth;
    var key = raw.trim().toLowerCase();
    return FRAME_DEPTHS.indexOf(key) !== -1 ? key : DEFAULT_LOOK_OPTIONS.frameDepth;
}

function frameDepthSpec(raw) {
    var key = normalizeFrameDepth(raw);
    var src = FRAME_DEPTH_SPECS[key] || FRAME_DEPTH_SPECS.off;
    return {
        id: src.id,
        keyOpacity: src.keyOpacity,
        aoOpacity: src.aoOpacity,
        sigma: src.sigma,
        aoSigma: src.aoSigma,
        offsetY: src.offsetY,
        extent: src.extent
    };
}

// A whole number inside [min, max]. Anything that is not a number (null, a
// boolean, an object, a blank or non-numeric string) gives `fallback`:
// Number("") is 0, which would otherwise clamp to the minimum.
function clampInt(value, min, max, fallback) {
    if (typeof value === "boolean" || value === null || value === undefined || typeof value === "object") {
        return fallback;
    }
    if (typeof value === "string" && value.trim() === "") return fallback;
    var n = Number(value);
    if (!isFinite(n)) return fallback;
    var r = Math.round(n);
    if (r < min) return min;
    if (r > max) return max;
    return r;
}

function normalizeLookOptions(raw) {
    var src = (raw && typeof raw === "object" && !Array.isArray(raw)) ? raw : {};
    var finish = typeof src.surfaceFinish === "string" ? src.surfaceFinish.trim().toLowerCase() : "";
    var motion = typeof src.motionProfile === "string" ? src.motionProfile.trim().toLowerCase() : "";

    return {
        frameThickness: clampInt(src.frameThickness, 4, 14, DEFAULT_LOOK_OPTIONS.frameThickness),
        innerRounding: clampInt(src.innerRounding, 8, 28, DEFAULT_LOOK_OPTIONS.innerRounding),
        surfaceFinish: finish === "solid" ? "solid" : DEFAULT_LOOK_OPTIONS.surfaceFinish,
        motionProfile: motion === "calm" ? "calm" : DEFAULT_LOOK_OPTIONS.motionProfile,
        frameDepth: normalizeFrameDepth(src.frameDepth)
    };
}

function linearizeChannel(c) {
    var v = Math.max(0, Math.min(1, Number(c) || 0));
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
}

// Accepts either a QML color object ({ r, g, b }) or a hex string
// (#RGB, #RRGGBB, or Qt's #AARRGGBB).
function parseColorChannels(color) {
    if (color && typeof color === "object" &&
        typeof color.r === "number" && typeof color.g === "number" && typeof color.b === "number") {
        return {
            r: Math.max(0, Math.min(1, color.r)),
            g: Math.max(0, Math.min(1, color.g)),
            b: Math.max(0, Math.min(1, color.b))
        };
    }
    if (typeof color !== "string") return { r: 0, g: 0, b: 0 };
    var hex = color.trim();
    if (hex.charAt(0) === "#") hex = hex.slice(1);
    if (hex.length === 3) {
        return {
            r: parseInt(hex.charAt(0) + hex.charAt(0), 16) / 255,
            g: parseInt(hex.charAt(1) + hex.charAt(1), 16) / 255,
            b: parseInt(hex.charAt(2) + hex.charAt(2), 16) / 255
        };
    }
    if (hex.length === 6) {
        return {
            r: parseInt(hex.slice(0, 2), 16) / 255,
            g: parseInt(hex.slice(2, 4), 16) / 255,
            b: parseInt(hex.slice(4, 6), 16) / 255
        };
    }
    if (hex.length === 8) {
        // Qt color string format is #AARRGGBB
        return {
            r: parseInt(hex.slice(2, 4), 16) / 255,
            g: parseInt(hex.slice(4, 6), 16) / 255,
            b: parseInt(hex.slice(6, 8), 16) / 255
        };
    }
    return { r: 0, g: 0, b: 0 };
}

function relativeLuminance(color) {
    var ch = parseColorChannels(color);
    return 0.2126 * linearizeChannel(ch.r)
         + 0.7152 * linearizeChannel(ch.g)
         + 0.0722 * linearizeChannel(ch.b);
}

function contrastRatio(colorA, colorB) {
    var l1 = relativeLuminance(colorA);
    var l2 = relativeLuminance(colorB);
    var hi = Math.max(l1, l2);
    var lo = Math.min(l1, l2);
    return (hi + 0.05) / (lo + 0.05);
}

function contrastInk(bg, darkInk, lightInk) {
    var dark = darkInk !== undefined && darkInk !== null ? darkInk : "#111111";
    var light = lightInk !== undefined && lightInk !== null ? lightInk : "#f5f5f5";
    return contrastRatio(bg, dark) >= contrastRatio(bg, light) ? dark : light;
}

// Clamp an attached frame drawer horizontally inside [minX, maxX - width]
// while keeping it centered on anchorCenterX when possible.
function clampDrawerX(anchorCenterX, drawerWidth, minX, maxX) {
    var span = Math.max(0, maxX - minX);
    var w = Math.max(0, Math.min(drawerWidth, span));
    var raw = Math.round(anchorCenterX - w / 2);
    if (raw < minX) return Math.round(minX);
    if (raw + w > maxX) return Math.round(maxX - w);
    return raw;
}

// Returns { [outputName]: boolean }: whether the window in front on that
// output's active workspace is a niri fullscreen window. niri's IPC has no
// fullscreen flag, so the test is the tile's size: only a fullscreen tile is
// as large as the screen (a maximized column stops at the gaps and the bar).
// It has to be the workspace's active window: a fullscreen column the view has
// scrolled away from keeps its size, but the bar is back on screen. A floating
// window of that size covers nothing niri hides the bar for.
function detectNiriFullscreenOutputs(windows, workspaces, screenSizesByName) {
    var out = {};
    var activeWs = {};
    var screens = (screenSizesByName && typeof screenSizesByName === "object") ? screenSizesByName : {};
    var screenKeys = Object.keys(screens);
    for (var k = 0; k < screenKeys.length; k++) {
        out[screenKeys[k]] = false;
    }
    var wsList = Array.isArray(workspaces) ? workspaces : [];
    for (var i = 0; i < wsList.length; i++) {
        var ws = wsList[i];
        if (!ws || typeof ws.output !== "string" || ws.output === "") continue;
        if (!(ws.output in out)) out[ws.output] = false;
        if (ws.is_active) activeWs[ws.id] = ws;
    }
    var winList = Array.isArray(windows) ? windows : [];
    for (var j = 0; j < winList.length; j++) {
        var w = winList[j];
        if (!w || w.is_floating === true) continue;
        var home = activeWs[w.workspace_id];
        if (!home || home.active_window_id !== w.id) continue;
        var scr = screens[home.output];
        if (!scr || !(scr.width > 0) || !(scr.height > 0)) continue;
        var lay = w.layout;
        var size = lay && Array.isArray(lay.tile_size) && lay.tile_size.length >= 2
            ? lay.tile_size
            : (lay && Array.isArray(lay.window_size) && lay.window_size.length >= 2 ? lay.window_size : null);
        if (!size) continue;
        var sw = Number(size[0]);
        var sh = Number(size[1]);
        if (!isFinite(sw) || !isFinite(sh)) continue;
        if (Math.abs(sw - scr.width) <= 2 && Math.abs(sh - scr.height) <= 2) {
            out[home.output] = true;
        }
    }
    return out;
}
