# tern-bar

A clean, floating top bar for the [niri](https://github.com/YaLTeR/niri) desktop. Everything sits in
small rounded "pills" that match your Tern theme.

![tern-bar](screenshots/bar.png)

## What you get

- Workspaces and the name of the window you're using
- Date and time
- What's playing, with a click to pause
- CPU and memory at a glance
- Wi-Fi, volume, notifications and a power button
- A system tray with proper right-click menus
- A Tern pill that shows how many terminal blocks you have open, and opens a new one
- An optional little desktop pet

## Set it up

You'll need [Quickshell](https://quickshell.org), niri, and the JetBrainsMono Nerd Font. For the
extras, volume uses PipeWire, notifications use `swaync`, and the buttons open `fuzzel`,
`pavucontrol` and `nm-connection-editor`.

```bash
git clone https://github.com/Tsukabe-Admin/tern-bar ~/.config/quickshell/tern-bar
quickshell -c tern-bar
```

To start it every time you log in, add this line to your niri config:

```kdl
spawn-at-startup "quickshell" "-c" "tern-bar"
```

Edit any file and the bar updates on the spot.

The bar looks for the `tern` app in `~/.local/bin`. If yours lives somewhere else, change
`ternBin` in `singletons/BarConfig.qml`. The small helper scripts it uses (power menu, network
status, IP hiding) are included in `scripts/`.

## Make it yours

- **Colors and sizes:** `singletons/Theme.qml`
- **Move the Tern pill:** right-click it to hop between the left, middle and right. The bar
  remembers your choice.
- **Launch animation:** there's a fancy "grow into a new window" effect. It's off by default. Turn it
  on with `morphEnabled` in `singletons/BarConfig.qml`, but don't run it in a loop.
- **Keybinding cheat sheet:** the launcher's right-click runs a script of your own. Point
  `cheatsheetScript` in `singletons/BarConfig.qml` at it, or ignore it.
- **Hide your IP:** click the network pill to hide or show your IP address.
- **Tray menus** close when you click anywhere else.

## What's inside

```
shell.qml        starts the bar on every screen
components/      the bar and each of its pills
singletons/      shared pieces: theme, settings, niri connection
scripts/         small helpers: power menu, network status, IP hiding
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
