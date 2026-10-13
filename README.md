# tern-bar

A clean, floating top bar for the [niri](https://github.com/YaLTeR/niri) desktop. Everything sits in
small rounded "pills" that can follow your wallpaper's colors.

![tern-bar](screenshots/bar.png)

## What you get

- Workspaces and the name of the window you're using
- An app launcher built into the bar: apps, open windows, a calculator, clipboard history and
  power actions, in a card that drops out of the launcher pill
- Quick settings: Wi-Fi, Bluetooth (with your paired devices), Do Not Disturb, night light and
  power profile
- A month calendar under the clock
- A small volume pop-up whenever the volume changes
- Date and time
- What's playing, with a click to pause
- CPU and memory at a glance
- Wi-Fi, volume, notifications and a power button
- A system tray with proper right-click menus
- A Tern pill that shows how many Tern windows are open, and opens a new one (only if you use Tern)
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
    Mod+B { spawn "quickshell" "ipc" "-c" "tern-bar" "call" "settings" "toggle"; }
    Mod+W { spawn "quickshell" "ipc" "-c" "tern-bar" "call" "settings" "wallpaper"; }
    Mod+Space { spawn "quickshell" "ipc" "-c" "tern-bar" "call" "launcher" "toggle"; }
    Mod+V { spawn "quickshell" "ipc" "-c" "tern-bar" "call" "launcher" "clipboard"; }
```

(If you already have a `binds { }` block, put those lines inside it instead. Other things a key can call:
`launcher power`, `launcher close`, `bar calendar`, `bar quickSettings`, `bar close`.)

Edit any file and the bar updates on the spot. Your own settings are saved in
`~/.config/tern-bar/`, never inside this folder, so `git pull` is always safe.

### Other programs it uses

Each one is only needed for the part it powers; the rest of the bar works without it.

| Program | Used for |
|---|---|
| `awww` (and its `awww-daemon`) | setting the wallpaper (Wallpaper tab) |
| `matugen` | colours taken from the wallpaper (the built-in themes don't need it) |
| `jq`, `python3` | the wallpaper and colour scripts |
| `zenity` | the "Change folder…" picker |
| `swaync` | the notification bell and Do Not Disturb (the bell hides itself without it) |
| `cliphist`, `wl-clipboard` | clipboard history in the launcher (with `wl-paste --watch cliphist store` running); copying calculator answers |
| `swaylock` | Lock and Suspend (without it, `loginctl lock-session` is used) |
| `wlsunset` | night light |
| `systemd` (`systemctl`, `loginctl`, `busctl`) | Suspend, Reboot and Power off; Lock when swaylock is missing; finding the power-profile service |
| `power-profiles-daemon` | the power profile switch |
| BlueZ, `blueman` | the Bluetooth tile and device list; the "Bluetooth settings" button |
| NetworkManager | the Wi-Fi tile |
| `pavucontrol`, PipeWire | right-click on volume; the volume pill itself |
| `nm-connection-editor`, `nmcli` or `iwgetid` | right-click on network; the Wi-Fi name |
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
the preset too.

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
- **Rearrange the bar:** open the settings page — the gear in the tools pill, a right-click on the
  launcher, or Mod+B — then drag a pill to another group or click it to show/hide it. Every change
  lands in `~/.config/tern-bar/bar.json`, and the page applies to all screens at once. Right-clicking the Tern pill
  still hops it straight to the next group. Any other key can call the same thing:
  `quickshell ipc -c tern-bar call settings toggle` (also `open` / `close`).
- **Wallpaper:** Mod+W, or the wallpaper button in the tools pill, opens the settings page straight
  on its Wallpaper tab — `quickshell ipc -c tern-bar call settings wallpaper` does the same, and
  pressing it again closes the page.
- **Launch animation:** there's a fancy "grow into a new window" effect. It's off by default. Turn it
  on with `morphEnabled` in `singletons/BarConfig.qml`, but don't run it in a loop.
- **Keybinding cheat sheet:** the `?` button in the tools pill shows niri's built-in hotkey overlay.
- **Launcher:** click the launcher pill (or Mod+Space). Type to search apps and open windows; type
  a sum like `2*(3+4)` to see the answer (Enter copies it); start with `;` to search clipboard
  history. Up/Down pick, Enter opens, Esc clears and then closes. Apps you open often move to the
  top (counts in `~/.local/state/tern-bar/launcher.json`). The ⏻ button opens the power actions;
  Log out, Reboot and Power off need a second Enter.
- **Quick settings:** the sliders button in the right-hand pill. **Calendar:** click the clock.
- **Your IP stays hidden:** the network pill shows only the Wi-Fi name until you click it; click
  again to hide the IP. The choice is the file `~/.local/state/tern-bar/show_ip`.
- **Tray menus** close when you click anywhere else.

## What's inside

```
shell.qml        starts the bar on every screen
components/      the bar and each of its pills
singletons/      shared pieces: theme, settings, wallpaper, niri connection
scripts/         helpers: wallpaper, colours, network status, IP hiding
themes/          the ten built-in colour themes
matugen/         an optional template, for driving the colours from your own matugen setup
screenshots/     pictures for this page
```

## If it misbehaves

To restart it by hand:

```bash
quickshell kill -c tern-bar
NIRI_SOCKET=$(ls /run/user/$UID/niri.wayland-1.*.sock) quickshell -c tern-bar --daemonize
```

Without `NIRI_SOCKET` the bar still starts, but workspaces and the window name stay empty.

## License

MIT. See `LICENSE`.
