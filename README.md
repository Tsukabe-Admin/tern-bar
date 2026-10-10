# tern-bar

A top bar for the [niri](https://github.com/YaLTeR/niri) Wayland compositor, built with
[Quickshell](https://quickshell.org). It is a row of capsules ("pills") styled after the active
Tern theme (`dark-midnight`), and it replaced waybar on 2026-10-08.

```
launcher · workspaces · window title  ‖  clock · media  ‖  cpu/mem · network · volume · tray · tools · notifications/power · Tern
```

## Requirements

| What | Used for |
| --- | --- |
| Quickshell 0.3.1 | runs the bar |
| niri 26.04 | workspaces and window title (IPC over `$NIRI_SOCKET`) |
| JetBrainsMono Nerd Font | text and icons |
| PipeWire | volume pill |
| `swaync` (`swaync-client`) | notification bell |
| `fuzzel`, `waypaper`, `pavucontrol`, `nm-connection-editor` | click actions |
| `~/.local/bin/tern` | Tern pill (live block count, opens Tern) |
| `~/.config/niri/scripts/` | `network-status.sh`, `toggle-ip-privacy.sh`, `cheatsheet.sh`, `powermenu.sh` |

The script and `tern` paths are hardcoded to `/home/tsu`. Change them in `BarPanel.qml`,
`Network.qml` and `singletons/Tern.qml` on another machine.

## Install and run

Quickshell finds a config by name in `~/.config/quickshell/<name>/`, so this repo lives at
`~/.config/quickshell/tern-bar`. niri starts it at login (`~/.config/niri/config.kdl`):

```kdl
spawn-at-startup "quickshell" "-c" "tern-bar"
```

Saving a `.qml` file reloads the bar live. A broken file keeps the last working version on screen,
so check the log for `Configuration Loaded` after an edit.

### Restarting by hand

The process is called `qs`, not `quickshell`. Pass `NIRI_SOCKET` explicitly: without it the bar
still runs but shows no workspaces and no window title. Do not pipe the output into `head`, because
that kills the bar.

```bash
pkill -f "qs -c tern-bar"
NIRI_SOCKET=$(ls /run/user/$UID/niri.wayland-1.*.sock) qs -c tern-bar --daemonize > /tmp/ternbar.log 2>&1
```

## Layout

| File | Role |
| --- | --- |
| `shell.qml` | entry point: one bar per screen |
| `BarPanel.qml` | the bar window and its three rows of pills |
| `Pill.qml`, `BarItem.qml`, `IconButton.qml` | capsule and item building blocks |
| `Workspaces.qml`, `WindowTitle.qml`, `Clock.qml`, `MprisPill.qml`, `Resources.qml`, `Network.qml`, `Volume.qml`, `Bell.qml` | modules |
| `Tray.qml`, `TrayMenu.qml` | system tray and its right-click menu, drawn in QML |
| `TernPill.qml`, `TernMorph.qml` | Tern pill and its optional launch animation |
| `singletons/Niri.qml` | niri IPC client (event stream, focus actions) |
| `singletons/Theme.qml` | colors, sizes, font |
| `singletons/BarConfig.qml`, `bar.json` | preferences; `bar.json` saves the Tern pill's side |
| `singletons/Tern.qml` | `tern ls --json` poller |

## Usage notes

- Right-click the Tern pill to move it between the left, center and right groups. The choice is
  saved in `bar.json`.
- The launch morph is off by default (`morphEnabled` in `singletons/BarConfig.qml`). Never trigger
  it on a repeating timer: a loop of it once crashed niri.
- Tray menus close when you click outside them. Escape cannot close them, because the menu never
  gets keyboard focus.
