#!/usr/bin/env bash
# Renders an ASCII wallpaper GIF for tern-bar's ASCII tab; all arguments go to
# tools/ascii/gen.mjs. Exit codes: 3 node missing, 4 `npm install` not run in
# tools/ascii, 5 ffmpeg missing, 1 anything gen.mjs reports.
set -uo pipefail
DIR="$(cd "$(dirname "$0")/../tools/ascii" && pwd)"
command -v node >/dev/null 2>&1 || { echo "ascii-render.sh: node is not installed" >&2; exit 3; }
if [ ! -d "$DIR/node_modules/ascii.rest" ] || [ ! -d "$DIR/node_modules/@napi-rs/canvas" ]; then
    echo "ascii-render.sh: run npm install in $DIR" >&2; exit 4
fi
command -v ffmpeg >/dev/null 2>&1 || { echo "ascii-render.sh: ffmpeg is not installed" >&2; exit 5; }
exec node "$DIR/gen.mjs" "$@"
