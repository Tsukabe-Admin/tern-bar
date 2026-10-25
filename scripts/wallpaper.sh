#!/usr/bin/env bash
# Put tern-bar's chosen wallpaper on screen with awww.
#
#   wallpaper.sh                        every screen, no transition (bar start, hotplug)
#   wallpaper.sh --animate              every screen, using the saved transition
#   wallpaper.sh --animate DP-3 DP-2    only the named screens
#
# Settings come from ${XDG_CONFIG_HOME:-~/.config}/tern-bar/wallpaper.json. The
# bar's Wallpaper tab is the only writer; this script only reads. A missing file,
# or a key that is absent or out of range, falls back to the defaults. A screen
# with no image of its own and no "All screens" image is left alone.
#
# Exit codes: 0 done (or nothing to do), 3 awww is not installed, 5 jq is not
# installed, 1 anything else.

set -uo pipefail

# Every setting below is read with jq; without it read_setting falls back to the
# defaults and the script would silently do nothing.
if ! command -v jq >/dev/null 2>&1; then
    echo "wallpaper.sh: jq is not installed" >&2
    exit 5
fi

STATE="${XDG_CONFIG_HOME:-$HOME/.config}/tern-bar/wallpaper.json"

ANIMATE=0
OUTPUTS=()
for arg in "$@"; do
    case "$arg" in
        --animate) ANIMATE=1 ;;
        *) OUTPUTS+=("$arg") ;;
    esac
done

# ── Settings ────────────────────────────────────────────────────────────────

# One field from the state file, or the fallback when the file is missing, the
# key is absent, the value has the wrong type, or the JSON is broken.
read_setting() {
    local value
    value=$(jq -r "$1" "$STATE" 2>/dev/null || true)
    case "$value" in "" | null) value="$2" ;; esac
    printf '%s' "$value"
}

FILL=$(read_setting '.fill | select(type == "string")' crop)
case "$FILL" in
    crop) RESIZE=crop ;;
    fit) RESIZE=fit ;;
    center) RESIZE=no ;;
    stretch) RESIZE=stretch ;;
    *) RESIZE=crop ;;
esac

# awww takes --fill-color as RRGGBBAA with no leading '#'.
FILL_COLOR=$(read_setting '.fillColor | select(type == "string")' '#000000')
[[ "$FILL_COLOR" =~ ^\#[0-9a-fA-F]{6}$ ]] || FILL_COLOR='#000000'
FILL_COLOR="${FILL_COLOR#\#}ff"

TRANSITION=$(read_setting '.transition | select(type == "string")' fade)
case "$TRANSITION" in
    fade | wipe | wave | grow | outer | left | random | none) ;;
    *) TRANSITION=fade ;;
esac
[ "$ANIMATE" = 1 ] || TRANSITION=none

DURATION=$(read_setting '.transitionDuration | select(type == "number")' 1.5)
[[ "$DURATION" =~ ^[0-9]+(\.[0-9]+)?$ ]] || DURATION=1.5

# ── Images ──────────────────────────────────────────────────────────────────

# The "All screens" image, or nothing when none is chosen or the file is gone.
star_image() {
    local image
    image=$(jq -r '.wallpapers["*"] // empty' "$STATE" 2>/dev/null || true)
    if [ -n "$image" ] && [ "${image#/}" != "$image" ] && [ -f "$image" ]; then
        printf '%s' "$image"
    fi
}

# A screen's own image when it has one that exists, else the "All screens" one.
image_for() {
    local image
    image=$(jq -r --arg o "$1" '.wallpapers[$o] // empty' "$STATE" 2>/dev/null || true)
    if [ -n "$image" ] && [ "${image#/}" != "$image" ] && [ -f "$image" ]; then
        printf '%s' "$image"
    else
        star_image
    fi
}

# ── Screens ─────────────────────────────────────────────────────────────────

SCREENS=("${OUTPUTS[@]}")
if [ ${#SCREENS[@]} -eq 0 ]; then
    mapfile -t SCREENS < <(niri msg --json outputs 2>/dev/null | jq -r 'keys[]' 2>/dev/null)
fi

# One command per distinct image, naming every screen that shows it. Screens that
# share an image animate together, which is what "All screens" should look like.
declare -A IMAGE_SCREENS=()
FALLBACK=""
if [ ${#SCREENS[@]} -eq 0 ]; then
    # No usable screen list (niri did not answer): the "All screens" image goes
    # on everything awww knows about.
    FALLBACK=$(star_image)
    [ -n "$FALLBACK" ] || exit 0
else
    for output in "${SCREENS[@]}"; do
        image=$(image_for "$output")
        [ -n "$image" ] || continue
        if [ -n "${IMAGE_SCREENS[$image]:-}" ]; then
            IMAGE_SCREENS[$image]="${IMAGE_SCREENS[$image]},$output"
        else
            IMAGE_SCREENS[$image]="$output"
        fi
    done
    [ ${#IMAGE_SCREENS[@]} -gt 0 ] || exit 0
fi

# ── Daemon ──────────────────────────────────────────────────────────────────
# Only reached when there is something to show. `awww img` talks to a running
# daemon: start one detached if there is none, then wait for it to answer (the
# socket appears a moment after the process does).

if ! command -v awww >/dev/null 2>&1 || ! command -v awww-daemon >/dev/null 2>&1; then
    echo "wallpaper.sh: awww is not installed" >&2
    exit 3
fi

if ! awww query >/dev/null 2>&1; then
    setsid -f awww-daemon --quiet >/dev/null 2>&1
fi

for _ in $(seq 1 50); do
    awww query >/dev/null 2>&1 && break
    sleep 0.1
done

if ! awww query >/dev/null 2>&1; then
    echo "wallpaper.sh: awww-daemon is not answering; wallpaper not set" >&2
    exit 1
fi

# ── Apply ───────────────────────────────────────────────────────────────────

if [ -n "$FALLBACK" ]; then
    exec awww img --resize "$RESIZE" --fill-color "$FILL_COLOR" -t "$TRANSITION" \
        --transition-duration "$DURATION" --transition-fps 60 "$FALLBACK"
fi

status=0
for image in "${!IMAGE_SCREENS[@]}"; do
    awww img -o "${IMAGE_SCREENS[$image]}" --resize "$RESIZE" --fill-color "$FILL_COLOR" \
        -t "$TRANSITION" --transition-duration "$DURATION" --transition-fps 60 "$image" || status=1
done

exit $status
