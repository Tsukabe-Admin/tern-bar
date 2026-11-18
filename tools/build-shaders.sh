#!/usr/bin/env bash
# Rebuilds shaders/*.frag.qsb from shaders/*.frag with Qt's shader baker (qsb).
#
#   tools/build-shaders.sh           rebuild every shader
#   tools/build-shaders.sh --check   rebuild into a scratch folder and compare what the files
#                                    hold; exit 1 when a committed .qsb does not match its source
#
# The bar loads the compiled .qsb files: in Qt 6 a ShaderEffect cannot take GLSL source. After
# editing a .frag, run this and commit the .frag and the .qsb together. qsb comes with Qt's
# shader tools (Arch: qt6-shadertools) and is usually not on the PATH; set QSB=/path/to/qsb if
# it is somewhere this script does not look.
#
# Exit codes: 0 done, 1 a .qsb is out of date (--check), 3 qsb not found, 4 qsb failed.
set -uo pipefail

DIR="$(cd "$(dirname "$0")/../shaders" && pwd)"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

QSB="${QSB:-}"
if [ -z "$QSB" ]; then
    for candidate in "$(command -v qsb 2>/dev/null)" /usr/lib/qt6/bin/qsb /usr/lib64/qt6/bin/qsb \
            /usr/lib/qt6/libexec/qsb "$(command -v qsb-qt6 2>/dev/null)"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            QSB="$candidate"
            break
        fi
    done
fi
[ -n "$QSB" ] && [ -x "$QSB" ] || {
    echo "build-shaders.sh: qsb not found (install Qt's shader tools, or set QSB=/path/to/qsb)" >&2
    exit 3
}

OUT="$DIR"
if [ "$CHECK" -eq 1 ]; then
    OUT="$(mktemp -d)" || exit 4
    trap 'rm -rf "$OUT"' EXIT
fi

stale=0
for src in "$DIR"/*.frag; do
    name="$(basename "$src")"
    # --qt6: the set Qt Quick wants (GLSL 100 es, 120, 150; HLSL 50; MSL 12) next to SPIR-V.
    "$QSB" --qt6 -o "$OUT/$name.qsb" "$src" || {
        echo "build-shaders.sh: qsb failed on $name" >&2
        exit 4
    }
    if [ "$CHECK" -eq 1 ]; then
        # What the two files hold is compared (qsb --dump: every variant of the shader and its
        # reflection data), not their bytes. A .qsb is compressed, and the same content comes
        # out as other bytes where zlib is another one (zlib-ng, say): a byte comparison only
        # ever passed on the machine that built the file.
        fresh="$("$QSB" --dump "$OUT/$name.qsb")" || {
            echo "build-shaders.sh: qsb could not read back $name.qsb" >&2
            exit 4
        }
        kept="$("$QSB" --dump "$DIR/$name.qsb" 2>/dev/null)"
        if [ -n "$fresh" ] && [ "$fresh" = "$kept" ]; then
            echo "ok     $name.qsb"
        else
            echo "stale  $name.qsb (rebuild it, or it was built by another Qt version than $("$QSB" --version 2>&1 | head -1))"
            stale=1
        fi
    else
        echo "built  $name.qsb"
    fi
done
exit "$stale"
