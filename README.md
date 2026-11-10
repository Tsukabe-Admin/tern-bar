# tern-bar

A clean, floating top bar for the [niri](https://github.com/YaLTeR/niri) desktop. Everything sits in
small rounded "pills" that can follow your wallpaper's colors.

![tern-bar](screenshots/bar.png)

## What you get

- Workspaces and the name of the window you're using
- An app launcher built into the bar: apps, open windows, a calculator, clipboard history and
  power actions, in a card that drops out of the launcher pill
- Quick settings: Wi-Fi, Bluetooth (with your paired devices), Do Not Disturb, night light,
  microphone mute, screen brightness and microphone input volume sliders, and power profile
- A month calendar and a five-day weather forecast under the clock and weather pills
- A small volume or brightness pop-up whenever the volume or screen brightness changes
- Date, time and current weather (condition icon + temperature, no API key needed)
- What's playing, with an expanded media player card (album art, track progress/seek bar, previous /
  play-pause / next, and a player switcher) on left-click, or quick play/pause on right/middle-click
- Pending Arch/Pacman/AUR package updates (`󰏗 <count>`), with a click to update in your terminal
- Active XKB keyboard layout indicator (`󰌌 US`, `JP`, …) from niri, with a click or scroll to switch
- System battery status with charging state and low-battery warnings (hidden on desktops without a battery)
- Microphone input status and mute pill (`󰍬` / `󰍭`) alongside output volume
- CPU and memory at a glance
- Wi-Fi, volume, notifications and a power button
- A system tray with proper right-click menus
- A Tern pill that shows how many Tern windows are open, and opens a terminal tab in one — or a new
  window when none is open (only if you use Tern)
- A wallpaper picker and colour controls, in the same window as the layout editor
- An optional little desktop pet — needs the tern-poke plugin for Tern (not released yet)

## Set it up

You'll need [Quickshell](https://quickshell.org) 0.3 or newer, [niri](https://github.com/YaLTeR/niri),
and the JetBrainsMono Nerd Font.

```bash
git clone https://github.com/Tsukabe-Admin/tern-bar ~/.config/quickshell/tern-bar
quickshell -c tern-bar
```

To start it every time you log in, and to make the settings window float, add this to your niri
config (`~/.config/niri/config.kdl`):

```kdl
spawn-at-startup "quickshell" "-c" "tern-bar"

window-rule {
    match title="^tern-bar settings$"
    match title="^Wallpaper folder$"
    open-floating true
}

binds {
    Mod+B repeat=false { spawn "quickshell" "ipc" "-c" "tern-bar" "call" "settings" "toggle"; }
    Mod+W repeat=false { spawn "quickshell" "ipc" "-c" "tern-bar" "call" "settings" "wallpaper"; }
    Mod+Space repeat=false { spawn "quickshell" "ipc" "-c" "tern-bar" "call" "launcher" "toggle"; }
    Mod+V repeat=false { spawn "quickshell" "ipc" "-c" "tern-bar" "call" "launcher" "clipboard"; }
    Mod+Return repeat=false { spawn "quickshell" "ipc" "-c" "tern-bar" "call" "tern" "open"; }
}
```

Keep the `repeat=false`: niri repeats a bind for as long as its key is held, and a repeated toggle
opens and closes the window many times a second.

(If you already have a `binds { }` block, put those lines inside it instead. Other things a key can call:
`launcher power`, `launcher close`, `bar calendar`, `bar media`, `bar quickSettings`, `bar close`,
`tern open`.)

Edit any file and the bar updates on the spot. Your own settings are saved in
`~/.config/tern-bar/`, never inside this folder, so `git pull` is always safe.

### Other programs it uses

Each one is only needed for the part it powers; the rest of the bar works without it.

| Program | Used for |
|---|---|
| `awww` (and its `awww-daemon`) | setting the wallpaper (Wallpaper tab) |
| `matugen` | colours taken from the wallpaper (the built-in themes don't need it) |
| `jq`, `python3` | the wallpaper, colour and weather scripts |
| `zenity` | the "Change folder…" picker |
| `swaync` | the notification bell and Do Not Disturb (the bell hides itself without it) |
| `cliphist`, `wl-clipboard` | clipboard history in the launcher (with `wl-paste --watch cliphist store` running); copying calculator answers |
| `swaylock` | Lock and Suspend (without it `loginctl lock-session` is sent instead, which only locks if a screen locker is listening for it) |
| `wlsunset` | night light |
| `brightnessctl`, `/sys/class/backlight` | the screen brightness slider in quick settings and the brightness OSD (hidden when no backlight device exists) |
| `checkupdates` (`pacman-contrib`), `paru` or `yay` | the package updates pill (hidden when 0 updates are pending or `pacman` is absent); a click runs the upgrade with `paru`, `yay` or `sudo pacman -Syu` |
| a terminal: `$TERMINAL`, else the first of `xdg-terminal-exec`, `kitty`, `foot`, `alacritty`, `ghostty`, `wezterm` | the upgrade started from the updates pill (without one the click does nothing), and launcher entries that run in a terminal |
| `systemd` (`systemctl`, `loginctl`, `busctl`, `udevadm`) | Suspend, Reboot and Power off; Lock when swaylock is missing; finding the power-profile service; backlight uevents |
| `power-profiles-daemon`, UPower | the power profile switch; the system battery pill (hidden on desktops without a battery) |
| BlueZ, `blueman` | the Bluetooth tile and device list; the "Bluetooth settings" button |
| NetworkManager | the Wi-Fi tile |
| `pavucontrol`, PipeWire | right-click on volume or microphone; the volume and microphone pills and quick-settings controls |
| `ip` (iproute2), `nm-connection-editor`, `nmcli` or `iwgetid` | the network pill (it reads "Offline" without `ip`); right-click on network; the Wi-Fi name |
| `notify-send` | the "IP hidden / shown" message |
| `tern` | the Tern pill — it hides itself when `tern` isn't on your PATH or in `~/.local/bin` |
| tern-poke (a Tern plugin, not released yet) | the PokeToken pill and the desktop pet — both stay hidden without it |

## Wallpaper and colors

The settings page has two tabs: **Layout** (see [Make it yours](#make-it-yours)) and **Wallpaper**.
The Wallpaper tab is a thumbnail grid of your wallpaper folder (`~/Pictures/Wallpapers` until you
pick another) — search, favourites, shuffle and automatic rotation — plus a per-screen choice (one
image everywhere, or a single screen with its own), fill mode and edge colour, animated
transitions, and the colour controls below. Wallpapers are drawn by `awww`; the bar starts it when
needed and puts your wallpaper back every time it starts. Until you pick one, the bar leaves your
desktop's wallpaper alone.

Everything the tab does is two scripts in `scripts/`: `wallpaper.sh` puts an image on screen and
`theme-sync.sh` recolours. Your choices are saved in `~/.config/tern-bar/wallpaper.json`; the bar is
its only writer.

### Colors from the wallpaper

With "Colours from wallpaper" on (and [matugen](https://github.com/InioX/matugen) installed), the
bar takes its colours from the *All screens* image, using the Material scheme and contrast you
pick. Without a wallpaper or matugen, it keeps its built-in dark blue colours. The bar always uses
the dark variant, whatever the wallpaper. Warning and OK colours stay yellow and green so they keep
their meaning.

If you already use matugen for other apps, nothing extra is needed: the same run also renders
the templates in your `~/.config/matugen/config.toml`.

### Built-in themes

Turn "Colours from wallpaper" off and the bar is painted from one of ten presets — Catppuccin
Mocha, Tokyo Night, Nord, Gruvbox Dark, Dracula, Rosé Pine, Everforest Dark, Kanagawa Wave, One
Dark, Solarized Dark — listed in `themes/presets.json`. They don't need matugen. Changing the
wallpaper then leaves the colours alone. If matugen is installed, your matugen templates follow
the preset too: a preset has thirteen colours, and every other Material role a template may ask
for is one of them or a mix of two (shadow and scrim are black).

### Recolour your other apps

After every recolour, `theme-sync.sh` runs `~/.config/tern-bar/theme-hook.sh` if it exists and is
executable, as `theme-hook.sh <colors.json> <label>`. `colors.json` holds every Material colour
role in matugen's format (`.colors.primary.default.color`, …), and `<label>` is the theme's name
or the wallpaper's file name. Use it to reload apps that don't notice new colours on their own,
for example `pkill -SIGUSR1 kitty`.

### Using your own matugen setup instead

If you'd rather run matugen yourself (from another wallpaper tool), add this to
`~/.config/matugen/config.toml` and don't use the Wallpaper tab's colour switch:

```toml
[templates.tern-bar]
input_path = "~/.config/quickshell/tern-bar/matugen/palette.json"
output_path = "~/.local/state/tern-bar/palette.json"
```

The bar watches that file and fades to the new colours. To change which Material You colour feeds
which part of the bar, edit `matugen/palette.json`.

## Make it yours

- **Sizes and the fallback colors:** `singletons/Theme.qml`
- **Crowded rows:** a row with four or more visible pills merges into one continuous island
  (`pillMergeThreshold` in `singletons/Theme.qml`). Set it to 5 to keep more capsules separate.
- **Rearrange the bar:** open the settings page — the gear in the tools pill, a right-click on the
  launcher, or Mod+B — then drag a pill to another group or click it to show/hide it. Every change
  lands in `~/.config/tern-bar/bar.json`, and the page applies to all screens at once. Right-clicking the Tern pill
  still hops it straight to the next group. Any other key can call the same thing:
  `quickshell ipc -c tern-bar call settings toggle` (also `open` / `close`). You can edit `bar.json` by
  hand too (restart the bar afterwards). If the edit leaves it invalid, the bar starts with the default
  layout, says so in its log, and keeps your text in `bar.json.bad` instead of losing it.
- **Wallpaper:** Mod+W, or the wallpaper button in the tools pill, opens the settings page straight
  on its Wallpaper tab — `quickshell ipc -c tern-bar call settings wallpaper` does the same, and
  pressing it again closes the page.
- **Album art:** the media popup only loads local cover art (`file:`, `image:`, `data:image`), because a
  remote `https` cover is a tracking pixel the player controls. Start the bar with `TERN_BAR_REMOTE_ART=1`
  to allow it.
- **Launch animation:** there's a fancy "grow into a new window" effect. It's off by default. Turn it
  on with `morphEnabled` in `singletons/BarConfig.qml`, but don't run it in a loop.
- **Keybinding cheat sheet:** the `?` button in the tools pill shows niri's built-in hotkey overlay.
- **Launcher:** click the launcher pill (or Mod+Space). Type to search apps and open windows; type
  a sum like `2*(3+4)` to see the answer (Enter copies it; whole numbers are exact up to 16 digits,
  anything larger or with a fraction is shown to 10 significant digits); start with `;` to search
  clipboard history. Up/Down pick, Enter opens, Esc clears and then closes. Apps you open often
  move to the top (counts in `~/.local/state/tern-bar/launcher.json`). The ⏻ button opens the power
  actions; Log out, Reboot and Power off need a second Enter (or click) within 3 seconds. Holding
  Enter down does not count, and moving the selection or typing cancels it.
- **Quick settings:** the sliders button in the right-hand pill. **Calendar:** click the clock.
- **Your IP stays hidden:** the network pill shows only the Wi-Fi name until you click it; click
  again to hide the IP. The choice is the file `~/.local/state/tern-bar/show_ip`.
- **Weather lookup:** the weather pill is on by default and asks a geolocation service
  (`ipwho.is`, or `wttr.in`) where you are, then fetches the forecast from Open-Meteo — no API
  key, but your IP is sent. Set `TERN_BAR_WEATHER_LOCATION="City"` or
  `TERN_BAR_WEATHER_COORDS="lat,lon"` in the bar's environment to skip the IP lookup.
- **Weather units:** open the forecast (click the weather or clock pill) and tap °C / °F. The
  choice is saved in `bar.json` (`weatherFahrenheit`); it re-formats the cached numbers, so no new
  fetch is needed.
- **Environment variables:** settings and generated files follow `XDG_CONFIG_HOME` and
  `XDG_STATE_HOME`; the folders named in this README are the defaults. `TERMINAL` chooses the
  terminal. For trying things without the real hardware or network: `TERN_BAR_BATTERY_MOCK="85:charging"`,
  `TERN_BAR_BACKLIGHT_DIR` (a folder to use instead of `/sys/class/backlight`),
  `TERN_BAR_UPDATES_MOCK=<count>`, `TERN_BAR_CHECKUPDATES_CMD`, `TERN_BAR_WEATHER_MOCK=<json>`, and the
  weather script's servers: `TERN_BAR_WEATHER_METEO_URL`, `TERN_BAR_WEATHER_WTTR_BASE`,
  `TERN_BAR_WEATHER_GEO_URL`, `TERN_BAR_WEATHER_GEOCODE_URL`.
- **Tray menus** close when you click anywhere else.
- **ASCII animations:** the settings window's **ASCII** tab (right-click the ASCII pill, or
  `quickshell ipc -c tern-bar call settings ascii`) picks a look, colour, speed, size and brightness for
  an animated ASCII wallpaper and renders it to a GIF that `awww` plays (about 15–45 s; saved in
  `<wallpaper folder>/ascii/`). The same tab sets the bar pill's piece, colour and speed, which apply
  at once; left-click the pill for the next piece. Choices are saved in `~/.config/tern-bar/ascii.json`.
  The launcher's "No matches" line uses the same player. The frames are plain text in `assets/ascii/`,
  so nothing is computed while the bar runs. Everything is made by `tools/ascii/gen.mjs` from
  [ascii.rest](https://github.com/bas3line/ascii) (MIT) looks. The pill, previews and launcher line work
  out of the box; rendering a wallpaper also needs `node`, `ffmpeg` and a one-time `npm install` in
  `tools/ascii` (the tab says which is missing). See `tools/ascii/README.md`.

## What's inside

```
shell.qml        starts the bar on every screen
components/      the bar and each of its pills
singletons/      shared pieces: theme, settings, wallpaper, niri connection
scripts/         helpers: wallpaper, colours, network status, IP hiding
themes/          the ten built-in colour themes
matugen/         an optional template, for driving the colours from your own matugen setup
screenshots/     pictures for this page
assets/ascii/    text frames for the ASCII pill and the launcher's empty state
tools/ascii/     generator for those frames and for animated ASCII wallpapers (needs node)
```

## If it misbehaves

To restart it by hand:

```bash
quickshell kill -c tern-bar
NIRI_SOCKET=$(ls /run/user/$UID/niri.wayland-1.*.sock) quickshell -c tern-bar --daemonize
```

Without `NIRI_SOCKET` the bar still starts, but workspaces and the window name stay empty.

## An experiment in vibecoding

This bar is an experiment in **vibecoding** — building software by describing what you want to an
AI coding agent and iterating on what it produces. The code here was mostly written by Claude Code
and OMP while I described the behaviour, tested it on the live desktop and decided what shipped.
It is a new way to work, and I wanted to see how far it can go: not a toy demo, but a daily-driver
bar with a launcher, settings, wallpaper tools, weather, media controls and the rest.

It runs every day on my machine (Arch, niri, Quickshell 0.3.2). It has not been tested on every
distro, GPU or Quickshell version, so treat it as a working experiment rather than a finished
product. The parts that matter were checked on the live desktop, not only compiled.

Bug reports, ideas, pull requests and questions are welcome — especially from people who know QML
or Quickshell better than I do. Screenshots of odd behaviour are just as useful as patches. I am
happy to help with this project or any other; open an issue or say hello. See
[CONTRIBUTING.md](CONTRIBUTING.md) for what is useful in a report or a PR.

## License

MIT. See `LICENSE`.
