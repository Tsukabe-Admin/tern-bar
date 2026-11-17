#!/usr/bin/env bash
# Put Skua's chosen wallpaper on screen with awww.
#
#   wallpaper.sh [--animate] --fill MODE --fill-color '#rrggbb' --transition NAME
#                --duration SECONDS --all IMAGE -- [SCREEN=IMAGE ...]
#
# The bar runs this with its Wallpaper tab's settings (~/.config/skua/wallpaper.json)
# spelled out, so the script reads no file. --all is the "All screens" image. Each
# SCREEN=IMAGE is a screen to paint and its own image, empty when it follows "All
# screens". With no screen named, the "All screens" image goes on every screen awww
# knows about. Without --animate the change is instant (bar start, hotplug). A value
# that is missing or out of range falls back to the default. A screen with no image
# of its own and no "All screens" image is left alone.
#
# Exit codes: 0 done (or nothing to do), 3 awww is not installed, 7 a chosen image is
# no longer there (after showing what it can), 1 anything else.

set -uo pipefail

ANIMATE=0
FILL=crop
FILL_COLOR='#000000'
TRANSITION=fade
DURATION=1.5
STAR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --animate) ANIMATE=1; shift ;;
        --fill | --fill-color | --transition | --duration | --all)
            if [ $# -lt 2 ]; then
                echo "wallpaper.sh: $1 needs a value" >&2
                exit 1
            fi
            case "$1" in
                --fill) FILL=$2 ;;
                --fill-color) FILL_COLOR=$2 ;;
                --transition) TRANSITION=$2 ;;
                --duration) DURATION=$2 ;;
                --all) STAR=$2 ;;
            esac
            shift 2 ;;
        --) shift; break ;;
        *)
            echo "wallpaper.sh: unknown argument: $1" >&2
            exit 1 ;;
    esac
done

# Each screen and the image chosen for it alone ("" = follows "All screens"). A
# screen name holds no "=", an image path may, so the split is at the first one.
SCREENS=()
declare -A OWN=()
for pair in "$@"; do
    case "$pair" in
        ?*=*)
            SCREENS+=("${pair%%=*}")
            OWN[${pair%%=*}]=${pair#*=} ;;
        *)
            echo "wallpaper.sh: expected SCREEN=IMAGE, got: $pair" >&2
            exit 1 ;;
    esac
done

# ── Settings ────────────────────────────────────────────────────────────────

case "$FILL" in
    crop) RESIZE=crop ;;
    fit) RESIZE=fit ;;
    center) RESIZE=no ;;
    stretch) RESIZE=stretch ;;
    *) RESIZE=crop ;;
esac

# awww takes --fill-color as RRGGBBAA with no leading '#'.
[[ "$FILL_COLOR" =~ ^\#[0-9a-fA-F]{6}$ ]] || FILL_COLOR='#000000'
FILL_COLOR="${FILL_COLOR#\#}ff"

case "$TRANSITION" in
    fade | wipe | wave | grow | outer | left | random | none) ;;
    *) TRANSITION=fade ;;
esac
[ "$ANIMATE" = 1 ] || TRANSITION=none

[[ "$DURATION" =~ ^[0-9]+(\.[0-9]+)?$ ]] || DURATION=1.5

# ── Images ──────────────────────────────────────────────────────────────────

# An image that can be shown: an absolute path to a file that is there. Absolute
# only, because the path is handed to `awww img`, where an option-like string
# (--help) would be read as a flag.
usable() {
    [ -n "$1" ] && [ "${1#/}" != "$1" ] && [ -f "$1" ]
}

# A chosen image that names a file that is no longer there. The screen then falls
# back as below; GONE makes the script say so at the end instead of looking as if
# nothing had been asked for.
gone() {
    [ -n "$1" ] && [ "${1#/}" != "$1" ] && [ ! -f "$1" ]
}
GONE=0

STAR_IMAGE=""
usable "$STAR" && STAR_IMAGE=$STAR

# ── Screens ─────────────────────────────────────────────────────────────────

# One command per distinct image, naming every screen that shows it. Screens that
# share an image animate together, which is what "All screens" should look like.
declare -A IMAGE_SCREENS=()
FALLBACK=""
if [ ${#SCREENS[@]} -eq 0 ]; then
    # No screen named: the "All screens" image goes on everything awww knows about.
    FALLBACK=$STAR_IMAGE
    if [ -z "$FALLBACK" ]; then
        gone "$STAR" && exit 7
        exit 0
    fi
else
    for output in "${SCREENS[@]}"; do
        own=${OWN[$output]}
        gone "$own" && GONE=1
        if usable "$own"; then
            image=$own
        elif [ -n "$STAR_IMAGE" ]; then
            image=$STAR_IMAGE
        else
            # Nothing of its own that exists: it wanted the "All screens" image.
            gone "$STAR" && GONE=1
            continue
        fi
        if [ -n "${IMAGE_SCREENS[$image]:-}" ]; then
            IMAGE_SCREENS[$image]="${IMAGE_SCREENS[$image]},$output"
        else
            IMAGE_SCREENS[$image]="$output"
        fi
    done
    if [ ${#IMAGE_SCREENS[@]} -eq 0 ]; then
        [ "$GONE" -eq 1 ] && exit 7
        exit 0
    fi
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

[ "$status" -eq 0 ] && [ "$GONE" -eq 1 ] && status=7
exit $status
