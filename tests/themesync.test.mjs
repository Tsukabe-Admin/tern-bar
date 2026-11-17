// Preset themes and the bar's palette (singletons/themesync.js). Run with: node --test tests/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// themesync.js is a QML script library: a ".pragma library" line and plain
// functions, no exports. Drop that line and it is ordinary JavaScript.
const source = readFileSync(new URL("../singletons/themesync.js", import.meta.url), "utf8")
    .replace(/^\.pragma library\s*$/m, "");
const lib = new Function(`${source}\nreturn { pickPreset, isUsablePreset, presetRoles, colorFile, paletteOf, matugenImageArgs };`)();
const presets = JSON.parse(readFileSync(new URL("../themes/presets.json", import.meta.url), "utf8"));

const roles = (id) => lib.presetRoles(lib.pickPreset(presets, id));

// Values the python3 expansion this replaced wrote for the same themes.
test("mixed roles match the python expansion, ties rounding to even", () => {
    const mocha = roles("catppuccin-mocha");
    // 116.5 and 146.5 are ties: python's round() gives 116 and 146 (#74, #92);
    // Math.round would give #756293 and move the colour.
    assert.equal(mocha.inverse_primary, "#746292");
    assert.equal(mocha.surface_container_low, "#282839");
    assert.equal(mocha.error_container, "#5e3f53");
    assert.equal(mocha.on_error_container, "#e0b0ce");
    assert.equal(mocha.primary_container, "#52476a");
    assert.equal(mocha.on_tertiary_container, "#e1ccee");
    assert.equal(mocha.secondary_fixed, "#abc5f7");

    const nord = roles("nord");
    assert.equal(nord.inverse_primary, "#5b7a88");
    assert.equal(nord.surface_container_low, "#343b49");
    assert.equal(nord.on_tertiary_container, "#d0bed0");
});

test("every theme expands to all fifty roles matugen writes", () => {
    for (const p of presets) {
        assert.ok(lib.isUsablePreset(p), p.id);
        const r = lib.presetRoles(p);
        assert.equal(Object.keys(r).length, 50, p.id);
        for (const [role, colour] of Object.entries(r))
            assert.match(colour, /^#[0-9a-fA-F]{6}$/, `${p.id} ${role}`);
        assert.equal(r.shadow, "#000000");
    }
});

test("an unknown theme id paints the first theme instead of nothing", () => {
    assert.equal(lib.pickPreset(presets, "no-such-theme"), presets[0]);
    assert.equal(lib.pickPreset([], "nord"), null);
});

test("a theme with a missing or malformed colour is refused", () => {
    const broken = Object.assign({}, presets[0]);
    delete broken.tertiary;
    assert.equal(lib.isUsablePreset(broken), false);
    assert.equal(lib.isUsablePreset(Object.assign({}, presets[0], { fg: "#abc" })), false);
    assert.equal(lib.isUsablePreset(null), false);
});

test("the palette is the dark variant of eight roles", () => {
    const file = lib.colorFile(roles("catppuccin-mocha"));
    file.colors.on_surface = { dark: { color: "#123456" }, light: { color: "#ffffff" } };
    const p = lib.paletteOf(file);
    assert.deepEqual(Object.keys(p), ["card", "ink", "muted", "dim", "faint", "accent", "live", "bad"]);
    assert.equal(p.ink, "#123456");
    assert.equal(p.card, presets[0].lowest);
    assert.equal(p.accent, presets[0].primary);
});

test("a role the colour file lacks leaves that palette slot empty", () => {
    const p = lib.paletteOf({ colors: { primary: { dark: { color: "#abcdef" } } } });
    assert.equal(p.accent, "#abcdef");
    assert.equal(p.card, null);
});

test("anything that is not a colour file is refused", () => {
    assert.throws(() => lib.paletteOf(null));
    assert.throws(() => lib.paletteOf({ colours: {} }));
    assert.throws(() => lib.paletteOf({ colors: "#000000" }));
});

test("a negative contrast reaches matugen as a value, not a flag", () => {
    const args = lib.matugenImageArgs("/w/a b.png", "scheme-vibrant", -0.5);
    assert.ok(args.includes("--contrast=-0.5"));
    assert.equal(args[args.length - 1], "/w/a b.png");
});
