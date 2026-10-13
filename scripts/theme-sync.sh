#!/usr/bin/env bash
# Recolour tern-bar, and (through matugen, if you use it) the rest of your desktop.
#
# The colours come from one of two sources, chosen by `colorSource` in
# ${XDG_CONFIG_HOME:-~/.config}/tern-bar/wallpaper.json (the bar writes it):
#
#   "wallpaper"  matugen reads the "All screens" image with the saved scheme and
#                contrast. Needs matugen.
#   "preset"     one of the themes in ../themes/presets.json (this repo). If
#                matugen is installed it runs too, so your own matugen templates
#                follow the preset.
#
# Writes, in ${XDG_STATE_HOME:-~/.local/state}/tern-bar/:
#   colors.json   every Material role, in matugen's JSON format
#   palette.json  the bar's eight colours; singletons/Theme.qml watches this file
#
# Then, if ${XDG_CONFIG_HOME:-~/.config}/tern-bar/theme-hook.sh exists and is
# executable, runs it as:   theme-hook.sh <path to colors.json> <label>
# where <label> is the preset's name or the wallpaper's file name. Use it to
# reload apps that do not watch their own colour files.
#
# Exit codes: 0 done, 3 matugen is not installed (wallpaper mode),
# 4 no "All screens" wallpaper to read (wallpaper mode), 1 anything else.

set -uo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tern-bar"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/tern-bar"
STATE="$CONFIG_DIR/wallpaper.json"
HOOK="$CONFIG_DIR/theme-hook.sh"
PRESETS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/themes/presets.json"

mkdir -p "$STATE_DIR" || exit 1
# Both files are built next to their final names and moved into place, so the
# bar never reads a half-written palette.
COLORS_TMP=$(mktemp "$STATE_DIR/.colors.XXXXXX") || exit 1
PALETTE_TMP=$(mktemp "$STATE_DIR/.palette.XXXXXX") || exit 1
trap 'rm -f "$COLORS_TMP" "$PALETTE_TMP"' EXIT

SOURCE=$(jq -r 'if .colorSource == "preset" then "preset" else "wallpaper" end' "$STATE" 2>/dev/null || true)
[ "$SOURCE" = preset ] || SOURCE=wallpaper

if [ "$SOURCE" = preset ]; then
    # ── Colours from a preset ──
    # Expand the preset's base colours into the Material roles matugen templates
    # use, in matugen's import format (one entry per role, each with the three
    # modes). Prints the preset's display name.
    PRESET_ID=$(jq -r '.preset // empty' "$STATE" 2>/dev/null || true)
    if ! LABEL=$(python3 - "$PRESETS" "$PRESET_ID" "$COLORS_TMP" << 'PYEOF'
import json, sys

presets_path, preset_id, out_path = sys.argv[1], sys.argv[2], sys.argv[3]


def to_rgb(value):
    value = value.lstrip("#")
    return [int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)]


def to_hex(rgb):
    return "#" + "".join("%02x" % max(0, min(255, round(c))) for c in rgb)


def mix(a, b, f):
    ca, cb = to_rgb(a), to_rgb(b)
    return to_hex([ca[i] + (cb[i] - ca[i]) * f for i in range(3)])


with open(presets_path) as f:
    presets = json.load(f)

preset = next((p for p in presets if p.get("id") == preset_id), None)
if preset is None:
    # Unknown id: fall back to the first preset rather than failing.
    preset = presets[0]

roles = {
    "surface_container_lowest": preset["lowest"],
    "surface": preset["surface"],
    "surface_container": preset["container"],
    "surface_container_high": preset["high"],
    "surface_container_highest": preset["highest"],
    "on_surface": preset["fg"],
    "on_surface_variant": preset["fgDim"],
    "outline": preset["outline"],
    "outline_variant": preset["outlineVariant"],
    "primary": preset["primary"],
    "secondary": preset["secondary"],
    "tertiary": preset["tertiary"],
    "error": preset["error"],
    "on_primary": preset["lowest"],
    "on_secondary": preset["lowest"],
    "on_tertiary": preset["lowest"],
    "primary_container": mix(preset["surface"], preset["primary"], 0.30),
    "secondary_container": mix(preset["surface"], preset["secondary"], 0.30),
    "primary_fixed": mix(preset["primary"], preset["fg"], 0.5),
}

out = {"colors": {role: {"default": {"color": c}, "dark": {"color": c}, "light": {"color": c}}
                  for role, c in roles.items()}}

with open(out_path, "w") as f:
    json.dump(out, f, indent=2)

print(preset["name"])
PYEOF
    ); then
        echo "theme-sync.sh: could not read $PRESETS" >&2
        exit 1
    fi

    if command -v matugen >/dev/null 2>&1; then
        matugen json "$COLORS_TMP" >/dev/null \
            || echo "theme-sync.sh: matugen json failed; only tern-bar was recoloured" >&2
    fi
else
    # ── Colours from the wallpaper ──
    if ! command -v matugen >/dev/null 2>&1; then
        echo "theme-sync.sh: matugen is not installed" >&2
        exit 3
    fi

    WALLPAPER=$(jq -r '.wallpapers["*"] // empty' "$STATE" 2>/dev/null || true)
    if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
        echo "theme-sync.sh: no \"All screens\" wallpaper to take colours from" >&2
        exit 4
    fi

    SCHEME=$(jq -r '.scheme // "scheme-tonal-spot"' "$STATE" 2>/dev/null || true)
    case "$SCHEME" in
        scheme-tonal-spot | scheme-vibrant | scheme-expressive | scheme-content | \
            scheme-fidelity | scheme-fruit-salad | scheme-rainbow | scheme-neutral | \
            scheme-monochrome) ;;
        *) SCHEME=scheme-tonal-spot ;;
    esac

    # contrast must survive as a number and stay inside -1..1.
    CONTRAST=$(jq -r '(.contrast // 0) | if type == "number" then ([., -1] | max | [., 1] | min) else 0 end' \
        "$STATE" 2>/dev/null || true)
    [ -n "$CONTRAST" ] || CONTRAST=0

    # --contrast takes the `=` form: a negative value such as -0.5 would
    # otherwise be read as a flag. -j hex prints the colours as JSON on stdout
    # while matugen still renders your own templates, if you have any.
    if ! matugen image -t "$SCHEME" --contrast="$CONTRAST" --source-color-index 0 \
        -j hex "$WALLPAPER" >"$COLORS_TMP"; then
        echo "theme-sync.sh: matugen could not read $WALLPAPER" >&2
        exit 1
    fi
    LABEL=$(basename "$WALLPAPER")
fi

# ── The bar's palette ──
# The bar is always dark, so it reads the dark variant of every role.
if ! jq '{card: .colors.surface_container_lowest.dark.color,
          ink: .colors.on_surface.dark.color,
          muted: .colors.on_surface_variant.dark.color,
          dim: .colors.outline.dark.color,
          faint: .colors.outline_variant.dark.color,
          accent: .colors.primary.dark.color,
          live: .colors.tertiary.dark.color,
          bad: .colors.error.dark.color}' "$COLORS_TMP" >"$PALETTE_TMP"; then
    echo "theme-sync.sh: matugen's colour data was not readable" >&2
    exit 1
fi

mv -f "$COLORS_TMP" "$STATE_DIR/colors.json" || exit 1
mv -f "$PALETTE_TMP" "$STATE_DIR/palette.json" || exit 1

if [ -x "$HOOK" ]; then
    "$HOOK" "$STATE_DIR/colors.json" "$LABEL" || echo "theme-sync.sh: theme-hook.sh exited $?" >&2
fi

exit 0
