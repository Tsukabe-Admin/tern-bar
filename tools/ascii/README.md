# tools/ascii

Makes ASCII animations for tern-bar from the "looks" in [ascii.rest](https://github.com/bas3line/ascii)
(MIT). Needs `node`, and `ffmpeg` for wallpapers. The bar itself never runs this except to render a
wallpaper when you press the ASCII tab's Render button (through `scripts/ascii-render.sh`); the pill
and the previews only play the files in `assets/ascii/`.

```sh
npm install
node gen.mjs list                                   # the 21 looks you can use
```

## Wallpapers

An animated GIF sized for a screen. `awww` plays it, and the Wallpaper tab lists any `.gif` in your
wallpaper folder. The ASCII tab is the usual way to make one; the same thing from a shell:

```sh
node gen.mjs wallpaper sea --out ~/Pictures/Wallpapers/ascii/sea.gif
node gen.mjs wallpaper tunnel --palette ocean --speed fast --size large --out tunnel.gif
node gen.mjs wallpaper sea --palette custom --color "#7aa2f7" --out sea-blue.gif
```

| option | default | |
| --- | --- | --- |
| `--out FILE.gif` | required | written atomically: a `.<name>.partial.gif` next to it until it is done |
| `--screen WxH` | `3440x1440` | pixel size of the GIF; a larger screen crops it, a smaller one scales it |
| `--palette` | `theme` | `theme` (the bar's colours, `~/.local/state/tern-bar/palette.json`), `custom`, or one of the 15 palettes in `assets/ascii/manifest.json` (`ocean`, `fire`, `neon`, …) |
| `--color #rrggbb` | | the colour for `--palette custom` |
| `--speed` | `normal` | `calm`, `slow`, `normal`, `fast`: the loop length (20, 12, 8, 5 s), so longer is slower |
| `--size` | `medium` | `small`..`huge`: how coarse the look's pattern is |
| `--brightness` | `0.6` | how bright the characters are against the background, 0.3 to 1 |

The cell size follows the screen (the kit draws at most 320 cells each way). While rendering it prints
`progress <n> <total>` and then `encoding`, which the ASCII tab turns into its status line.

Measured on this machine: a 3440x1440 loop is 1 to 16 MB and takes about 20 to 30 s to render, and
`awww-daemon` holds about 110 MB while playing it at roughly 3% CPU.

Colours are fixed when the GIF is made. After a theme change, render again if you want them to match.

## Bar assets

```sh
node gen.mjs assets
```

Deletes and rewrites every `*.json` in `assets/ascii/`: `manifest.json` (the looks, palettes, pill pieces
and speeds the ASCII tab offers), `pill-<look>.json` (14x2, for the bar pill), `preview-<look>.json`
(28x7, for the tab's tiles) and `drift.json` (the launcher's "No matches" line). The frames are plain
text, tinted by `components/AsciiArt.qml` at run time.

To change what the tab offers, edit the tables at the top of `gen.mjs` (`LOOKS`, `PILL_PIECES`,
`PALETTES`) and run `assets` again. Pill pieces must use characters from the bar's font and show up at two
rows: `matrix` uses katakana, which is not in the font, and `sun`, `ripple`, `plume` and `galaxy` are
nearly empty that small.
