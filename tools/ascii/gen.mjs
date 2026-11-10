#!/usr/bin/env node
// Turns ascii.rest "looks" (https://github.com/bas3line/ascii, MIT) into things
// tern-bar can show. Two outputs:
//
//   wallpaper <look>   an animated GIF sized for a screen, which `awww img` plays
//   assets             the small JSON files the bar plays itself: the pill's
//                      pieces, the ASCII tab's previews, and a manifest listing
//                      every look, palette and speed
//
//   node gen.mjs list
//   node gen.mjs wallpaper aurora --out ~/Pictures/Wallpapers/ascii/aurora.gif
//   node gen.mjs wallpaper sea --palette fire --speed fast --size large --out sea.gif
//   node gen.mjs wallpaper sea --palette custom --color "#7aa2f7" --out sea.gif
//   node gen.mjs assets
//
// `--palette theme` (the default) draws in the bar's current colours:
// palette.json in $XDG_STATE_HOME/tern-bar (~/.local/state/tern-bar), or the
// bar's built-in colours while that file does not exist yet. Any other palette
// id is listed in the manifest.
//
// While rendering a wallpaper it prints `progress <n> <total>` per frame and
// `encoding` before the GIF is assembled; the ASCII tab reads those lines.

import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

// The two packages this needs are loaded by load(), from main(), and not by
// `import` lines here. An `import` that throws (the canvas package without its
// native part, say) does so before any code in this file runs, so nothing could
// report it the way every other failure is reported.
let kit;
let createCanvas, GlobalFonts;

// id -> [function name in the kit, name shown in the UI]. The one list every
// other table refers to.
const LOOKS = {
    aurora: ["aurora", "Aurora"],
    clouds: ["clouds", "Clouds"],
    flames: ["flames", "Flames"],
    galaxy: ["galaxy", "Galaxy"],
    "lava-lamp": ["lavaLamp", "Lava lamp"],
    marble: ["marble", "Marble"],
    matrix: ["matrix", "Matrix"],
    plasma: ["plasma", "Plasma"],
    plume: ["plume", "Plume"],
    rainfall: ["rainfall", "Rainfall"],
    rings: ["rings", "Rings"],
    ripple: ["ripple", "Ripple"],
    sea: ["sea", "Sea"],
    snowfall: ["snowfall", "Snowfall"],
    spiral: ["spiral", "Spiral"],
    stars: ["stars", "Stars"],
    sun: ["sun", "Sun"],
    tunnel: ["tunnel", "Tunnel"],
    turbulence: ["turbulence", "Turbulence"],
    vortex: ["vortex", "Vortex"],
    waves: ["waves", "Waves"],
};

// Legible at 14x2. matrix needs katakana (not in JetBrainsMono); sun, ripple,
// plume and galaxy are nearly empty at two rows.
const PILL_PIECES = ["waves", "flames", "stars", "rainfall", "snowfall", "sea", "aurora", "clouds", "lava-lamp", "rings", "tunnel"];

const PALETTES = [
    ["ocean", "Ocean"], ["sunset", "Sunset"], ["neon", "Neon"], ["fire", "Fire"], ["aurora", "Aurora"],
    ["forest", "Forest"], ["candy", "Candy"], ["ice", "Ice"], ["gold", "Gold"], ["lava", "Lava"],
    ["matrix", "Terminal"], ["night", "Night"], ["space", "Space"], ["paper", "Paper"], ["mono", "Mono"],
];

// seconds is the loop length, so a longer loop is slower motion.
const WALLPAPER_SPEEDS = { calm: { seconds: 20, fps: 8 }, slow: { seconds: 12, fps: 10 }, normal: { seconds: 8, fps: 10 }, fast: { seconds: 5, fps: 12 } };
const PILL_SPEEDS = ["slow", "normal", "fast"];
const SIZES = ["small", "medium", "large", "huge"];

const GRAY_PALETTE = ["#000000", "#111111", "#222222", "#333333"];

const FONT_FAMILY = "JetBrainsMono Nerd Font";
const FONT_ADVANCE = 0.6; // a JetBrains Mono cell is 0.6 em wide

// What a command stops with: one line for the user. It is thrown rather than
// printed and followed by process.exit(), because exit() skips the `finally`
// blocks that remove a render's scratch frames. The end of this file catches it.
class Failure extends Error {}

function fail(message) {
    throw new Failure(message);
}

function expand(path) {
    return path.startsWith("~/") ? join(homedir(), path.slice(2)) : resolve(path);
}

// ── Colour ──────────────────────────────────────────────────────────────────

const HEX = /^#[0-9a-fA-F]{6}$/;

function rgb(hex) {
    return [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
}

function hex(channels) {
    return "#" + channels.map((c) => Math.round(Math.min(255, Math.max(0, c))).toString(16).padStart(2, "0")).join("");
}

// `amount` of the way from colour a to colour b.
function mix(a, b, amount) {
    const from = rgb(a);
    const to = rgb(b);
    return hex(from.map((c, i) => c + (to[i] - c) * amount));
}

// The bar's colours, for `--palette theme`. scripts/theme-sync.sh writes them to
// palette.json in the state folder, the same one singletons/BarConfig.qml and
// the scripts work out. Until a theme has been applied that file does not exist
// and the bar shows the fallbacks in singletons/Theme.qml, so they are used here
// too: keep the four in step with that file.
const THEME_FALLBACK = { card: "#050F16", faint: "#263238", accent: "#2979FF", live: "#00E5FF" };

function loadTheme() {
    const file = join(process.env.XDG_STATE_HOME || join(homedir(), ".local/state"), "tern-bar/palette.json");
    let text;
    try {
        text = readFileSync(file, "utf8");
    } catch (error) {
        if (error.code === "ENOENT") return THEME_FALLBACK;
        fail(`cannot read the theme ${file}: ${error.message}`);
    }
    let json;
    try {
        json = JSON.parse(text);
    } catch (error) {
        fail(`cannot read the theme ${file}: ${error.message}`);
    }
    for (const key of ["card", "faint", "accent", "live"]) {
        if (typeof json[key] !== "string" || !HEX.test(json[key])) fail(`theme ${file}: "${key}" is not #rrggbb`);
    }
    return json;
}

// ── Palettes ────────────────────────────────────────────────────────────────

// The kit's palettes as the manifest and resolvePalette() want them. Filled by load().
let palettes = [];

async function load() {
    kit = await import("ascii.rest/kit");
    ({ createCanvas, GlobalFonts } = await import("@napi-rs/canvas"));
    palettes = PALETTES.map(([id, name]) => {
        const colors = kit.palette(id).dark;
        return {
            id,
            name,
            background: mix("#000000", colors[0], 0.3),
            colors,
            accent: colors[Math.floor(colors.length * 0.6)],
        };
    });
}

// { background, colors } with colors faint to strong.
function resolvePalette({ palette, color }) {
    if (palette === "theme") {
        const theme = loadTheme();
        return { background: theme.card, colors: [theme.faint, theme.accent, theme.live] };
    }
    const entry = palettes.find((p) => p.id === palette);
    if (entry) return entry;
    if (palette === "custom") {
        if (typeof color !== "string" || !HEX.test(color)) fail("--color must be #rrggbb");
        const background = mix("#000000", color, 0.08);
        return { background, colors: [mix(background, color, 0.35), color, mix(color, "#ffffff", 0.35)] };
    }
    return fail(`unknown palette "${palette}". Try: theme, custom, ${palettes.map((p) => p.id).join(", ")}`);
}

// ── Looks ───────────────────────────────────────────────────────────────────

// `palette` is the final colour list, faint to strong, background first.
function buildLook(id, { palette, cols, rows, seconds, scale }) {
    const entry = LOOKS[id];
    if (!entry || typeof kit[entry[0]] !== "function") {
        fail(`unknown look "${id}". Try: ${Object.keys(LOOKS).join(", ")}`);
    }
    const options = { palette, cols, rows };
    if (seconds) options.period = seconds;
    if (scale) options.scale = scale;
    return kit[entry[0]](options);
}

// Samples a look: text and a palette index per cell for each of `count` frames,
// spread evenly over one loop so the last frame leads straight back to the first.
function sample(look, count, seconds) {
    const frame = look.default();
    const { cols, rows } = look.meta;
    const frames = [];
    for (let i = 0; i < count; i++) {
        const color = new Uint8Array(cols * rows);
        const text = frame((i * seconds) / count, { color });
        frames.push({ text, color });
    }
    return frames;
}

// ── Wallpaper ───────────────────────────────────────────────────────────────

function run(command, args) {
    const result = spawnSync(command, args, { stdio: ["ignore", "ignore", "pipe"], encoding: "utf8" });
    if (result.status !== 0) fail(`${command} failed: ${result.stderr || result.error}`);
}

// A folder for one render's frames. A render that is killed cannot remove its
// own (the bar reloading in the middle of one does that), so each new render
// first removes what such runs left: same name, untouched for an hour. That
// tidying is a courtesy: if the temp folder cannot even be listed, the render
// still gets its folder.
function scratchDir(kind) {
    const prefix = `ascii-${kind}-`;
    try {
        for (const name of readdirSync(tmpdir())) {
            if (!name.startsWith(prefix)) continue;
            const stale = join(tmpdir(), name);
            try {
                if (Date.now() - statSync(stale).mtimeMs > 3600000) rmSync(stale, { recursive: true, force: true });
            } catch {
                // someone else's, or gone already
            }
        }
    } catch {
        // nothing to tidy that we can see
    }
    return mkdtempSync(join(tmpdir(), prefix));
}

async function wallpaper(id, values) {
    const [width, height] = values.screen.split("x").map(Number);
    if (![width, height].every((n) => Number.isInteger(n) && n > 0)) {
        fail("--screen is WIDTHxHEIGHT in whole pixels, like 3440x1440");
    }
    const speed = WALLPAPER_SPEEDS[values.speed];
    if (!speed) fail(`--speed is one of ${Object.keys(WALLPAPER_SPEEDS).join(", ")}`);
    if (!SIZES.includes(values.size)) fail(`--size is one of ${SIZES.join(", ")}`);
    const brightness = Number(values.brightness);
    if (!(brightness >= 0.3 && brightness <= 1)) fail("--brightness is 0.3 to 1");

    const { background, colors } = resolvePalette({ palette: values.palette, color: values.color });

    // The kit draws at most 320 cells each way.
    const cellW = Math.max(12, Math.ceil(width / 320));
    let cellH = 2 * cellW;
    if (Math.ceil(height / cellH) > 320) cellH = Math.ceil(height / 320);
    const cols = Math.ceil(width / cellW);
    const rows = Math.ceil(height / cellH);

    const { seconds, fps } = speed;
    const palette = [background, ...colors.map((c) => mix(background, c, brightness))];
    const look = buildLook(id, { palette, cols, rows, seconds, scale: values.size });
    const count = Math.round(fps * seconds);
    const frames = sample(look, count, seconds);
    const style = look.meta.palette;

    const canvas = createCanvas(width, height);
    const ctx = canvas.getContext("2d");
    ctx.font = `${cellW / FONT_ADVANCE}px "${FONT_FAMILY}"`;
    ctx.textBaseline = "middle";

    const out = expand(values.out);
    mkdirSync(dirname(out), { recursive: true });
    // A leading dot keeps a half-written file out of the wallpaper picker.
    const partial = join(dirname(out), "." + basename(out, ".gif") + ".partial.gif");
    const scratch = scratchDir("wallpaper");
    try {
        for (let n = 0; n < frames.length; n++) {
            ctx.fillStyle = background;
            ctx.fillRect(0, 0, width, height);
            const lines = frames[n].text.split("\n");
            const { color } = frames[n];
            let lastStyle = "";
            for (let y = 0; y < rows; y++) {
                const line = lines[y] ?? "";
                for (let x = 0; x < cols; x++) {
                    const ch = line[x];
                    if (ch === undefined || ch === " ") continue;
                    const fill = style[color[y * cols + x]];
                    if (fill !== lastStyle) {
                        ctx.fillStyle = fill;
                        lastStyle = fill;
                    }
                    ctx.fillText(ch, x * cellW, y * cellH + cellH / 2);
                }
            }
            writeFileSync(join(scratch, `f${String(n).padStart(4, "0")}.png`), canvas.toBuffer("image/png"));
            console.log(`progress ${n + 1} ${count}`);
        }

        // Two passes so one palette serves every frame: a per-frame palette makes
        // the colours shimmer. GIF delays are whole hundredths of a second.
        console.log("encoding");
        const input = ["-framerate", String(fps), "-i", join(scratch, "f%04d.png")];
        const palettePng = join(scratch, "palette.png");
        run("ffmpeg", ["-v", "error", "-y", ...input, "-vf", "palettegen=max_colors=96:stats_mode=full", palettePng]);
        run("ffmpeg", [
            "-v", "error", "-y", ...input, "-i", palettePng,
            "-lavfi", "paletteuse=dither=none", "-loop", "0", partial,
        ]);
        renameSync(partial, out);
        console.log(`${out}  ${width}x${height}  ${count} frames at ${fps} fps  (${cols}x${rows} cells)`);
    } finally {
        rmSync(scratch, { recursive: true, force: true });
        rmSync(partial, { force: true });
    }
}

// ── Bar assets ──────────────────────────────────────────────────────────────

// Text frames for components/AsciiArt.qml, which tints the text itself, so the
// strength of a cell is carried by its character and the palette only has to
// exist.
function frameFile(name, id, { cols, rows, seconds, fps, scale }) {
    const look = buildLook(id, { palette: GRAY_PALETTE, cols, rows, seconds, scale });
    const count = Math.round(fps * seconds);
    const frames = sample(look, count, seconds).map((f) => f.text.split("\n").map((l) => l.padEnd(cols).slice(0, cols)).join("\n"));
    return JSON.stringify({ name, cols, rows, fps, frames }) + "\n";
}

function assets() {
    const dir = join(dirname(fileURLToPath(import.meta.url)), "../../assets/ascii");
    mkdirSync(dir, { recursive: true });
    for (const file of readdirSync(dir)) if (file.endsWith(".json")) rmSync(join(dir, file));

    const looks = Object.entries(LOOKS).map(([id, [, name]]) => ({ id, name }));
    const manifest = {
        looks,
        palettes,
        pillPieces: PILL_PIECES.map((id) => ({ id, name: LOOKS[id][1] })),
        wallpaperSpeeds: Object.keys(WALLPAPER_SPEEDS),
        pillSpeeds: PILL_SPEEDS,
        sizes: SIZES,
    };
    writeFileSync(join(dir, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");

    for (const id of PILL_PIECES) {
        writeFileSync(join(dir, `pill-${id}.json`), frameFile(`pill-${id}`, id, { cols: 14, rows: 2, seconds: 6, fps: 10 }));
    }
    for (const { id } of looks) {
        writeFileSync(join(dir, `preview-${id}.json`), frameFile(`preview-${id}`, id, { cols: 28, rows: 7, seconds: 8, fps: 10 }));
    }
    // The launcher's empty state.
    writeFileSync(join(dir, "drift.json"), frameFile("drift", "waves", { cols: 28, rows: 3, seconds: 8, fps: 10, scale: "large" }));
    console.log(`${dir}  manifest, drift, ${PILL_PIECES.length} pill, ${looks.length} preview`);
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
    const { positionals, values } = parseArgs({
        allowPositionals: true,
        options: {
            screen: { type: "string", default: "3440x1440" },
            palette: { type: "string", default: "theme" },
            color: { type: "string" },
            speed: { type: "string", default: "normal" },
            size: { type: "string", default: "medium" },
            brightness: { type: "string", default: "0.6" },
            out: { type: "string" },
        },
    });

    const [command, name] = positionals;
    await load();
    GlobalFonts.families; // loads the system fonts before the first draw

    if (command === "list") {
        console.log(Object.keys(LOOKS).join("\n"));
    } else if (command === "assets") {
        assets();
    } else if (command === "wallpaper" && name) {
        if (!values.out) fail("--out is required");
        await wallpaper(name, values);
    } else {
        fail("usage: gen.mjs list | assets | wallpaper <look> --out FILE.gif [--palette P --color #rrggbb --speed S --size Z --brightness B --screen WxH]");
    }
}

try {
    await main();
} catch (error) {
    // The ASCII tab shows the last line of stderr, so the reason is one line and
    // comes last. Anything that was not expected gets its stack too, above it.
    if (!(error instanceof Failure)) console.error(error?.stack ?? error);
    console.error(`gen.mjs: ${error?.message ?? error}`);
    process.exit(1);
}
