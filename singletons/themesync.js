.pragma library

// The colour work behind the Wallpaper tab's recolour, in plain JavaScript so it
// needs neither jq nor python3: expanding a preset theme into every Material role
// a matugen template may ask for, and cutting the bar's eight colours out of a
// matugen colour file. Wallpaper.qml runs matugen and writes the files.

// The thirteen colours every theme in themes/presets.json carries.
var PRESET_KEYS = ["lowest", "surface", "container", "high", "highest", "fg", "fgDim",
    "outline", "outlineVariant", "primary", "secondary", "tertiary", "error"];

// The bar's eight colours and the role each one comes from (palette.json's keys;
// singletons/Theme.qml reads them). matugen/palette.json maps the same roles for
// people who run matugen themselves: change both together.
var PALETTE_ROLES = {
    card: "surface_container_lowest",
    ink: "on_surface",
    muted: "on_surface_variant",
    dim: "outline",
    faint: "outline_variant",
    accent: "primary",
    live: "tertiary",
    bad: "error"
};

// Python's round(): a half goes to the even neighbour (116.5 -> 116). The mixes
// below were first written with it, so Math.round would move some channels of
// existing themes by one.
function roundHalfEven(x) {
    var r = Math.round(x);
    if (Math.abs(x % 1) === 0.5 && r % 2 !== 0)
        r -= 1;
    return r;
}

function toRgb(hex) {
    return [parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16)];
}

function toHex(rgb) {
    return "#" + rgb.map(function (c) {
        var v = Math.max(0, Math.min(255, roundHalfEven(c)));
        return (v < 16 ? "0" : "") + v.toString(16);
    }).join("");
}

// `a` moved the fraction `f` of the way towards `b`, channel by channel.
function mix(a, b, f) {
    var ca = toRgb(a);
    var cb = toRgb(b);
    return toHex([0, 1, 2].map(function (i) { return ca[i] + (cb[i] - ca[i]) * f; }));
}

// True when `p` has all thirteen colours as #rrggbb, so a hand-edited theme with
// a typo is reported instead of painting the bar from garbage.
function isUsablePreset(p) {
    if (!p || typeof p !== "object")
        return false;
    return PRESET_KEYS.every(function (key) {
        return typeof p[key] === "string" && /^#[0-9a-fA-F]{6}$/.test(p[key]);
    });
}

// The theme with this id. An unknown id (a theme renamed or removed since it was
// picked) gets the first theme rather than no colours at all.
function pickPreset(presets, id) {
    if (!Array.isArray(presets) || presets.length === 0)
        return null;
    for (var i = 0; i < presets.length; i++) {
        if (presets[i] && presets[i].id === id)
            return presets[i];
    }
    return presets[0];
}

// A theme has thirteen colours and matugen's scheme has fifty roles. Each role
// gets one of the thirteen or a mix of two of them, following how a dark
// Material scheme relates its tones; shadow and scrim are black. The lines below
// are the whole rule, role by role, so a template may use any role matugen itself
// writes. The order is the order of the file.
function presetRoles(p) {
    var roles = {
        background: p.surface,
        on_background: p.fg,
        surface_dim: p.surface,
        surface: p.surface,
        surface_bright: p.highest,
        surface_container_lowest: p.lowest,
        surface_container_low: mix(p.surface, p.container, 0.5),
        surface_container: p.container,
        surface_container_high: p.high,
        surface_container_highest: p.highest,
        surface_variant: p.outlineVariant,
        surface_tint: p.primary,
        on_surface: p.fg,
        on_surface_variant: p.fgDim,
        inverse_surface: p.fg,
        inverse_on_surface: p.high,
        inverse_primary: mix(p.surface, p.primary, 0.5),
        outline: p.outline,
        outline_variant: p.outlineVariant,
        shadow: "#000000",
        scrim: "#000000",
        source_color: p.primary,
        error: p.error,
        on_error: p.lowest,
        error_container: mix(p.surface, p.error, 0.30),
        on_error_container: mix(p.error, p.fg, 0.5)
    };
    ["primary", "secondary", "tertiary"].forEach(function (name) {
        var colour = p[name];
        roles[name] = colour;
        roles["on_" + name] = p.lowest;
        roles[name + "_container"] = mix(p.surface, colour, 0.30);
        roles["on_" + name + "_container"] = mix(colour, p.fg, 0.5);
        roles[name + "_fixed"] = mix(colour, p.fg, 0.5);
        roles[name + "_fixed_dim"] = colour;
        roles["on_" + name + "_fixed"] = p.lowest;
        roles["on_" + name + "_fixed_variant"] = mix(p.surface, colour, 0.30);
    });
    return roles;
}

// The roles in matugen's colour-file format (`matugen json` reads it back). A
// theme has one colour per role, so all three modes carry the same one.
function colorFile(roles) {
    var colors = {};
    Object.keys(roles).forEach(function (role) {
        var c = roles[role];
        colors[role] = { "default": { color: c }, dark: { color: c }, light: { color: c } };
    });
    return { colors: colors };
}

// The bar's eight colours from a matugen colour file, from the dark variant of
// each role: the bar is always dark. A role the file lacks comes out null, and
// Theme.qml keeps its built-in colour for it. Throws when `data` is not a colour
// file at all.
function paletteOf(data) {
    if (!data || typeof data !== "object" || !data.colors || typeof data.colors !== "object")
        throw new Error("not a matugen colour file");
    var out = {};
    Object.keys(PALETTE_ROLES).forEach(function (key) {
        var role = data.colors[PALETTE_ROLES[key]];
        var c = (role && role.dark) ? role.dark.color : undefined;
        out[key] = (typeof c === "string") ? c : null;
    });
    return out;
}

// matugen's arguments for colours taken from `image`. --contrast takes the `=`
// form: a negative value such as -0.5 would otherwise be read as a flag. -j hex
// prints the colours as JSON while matugen still renders your own templates.
function matugenImageArgs(image, scheme, contrast) {
    return ["image", "-t", scheme, "--contrast=" + contrast, "--source-color-index", "0",
        "-j", "hex", image];
}
