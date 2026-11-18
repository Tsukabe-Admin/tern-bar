# tools/skua-helper

`skua-helper` is Skua's helper program: the jobs a Quickshell bar cannot do in QML because they need
a small program running in the background. Each job is a subcommand, and the bar runs each one as a
process of its own, so one job failing never stops another.

| Job | What it does |
|---|---|
| `skua-helper bluetooth` | answers BlueZ's pairing questions (a PIN, a passkey, "does the device show 123456?") through the bar |
| `skua-helper night-light` | warms the screens' colours (night light) through the compositor's gamma control |
| `skua-helper clipboard` | keeps the clipboard history the launcher lists after `;`, and puts an entry back on the clipboard (replaces cliphist and wl-clipboard) |

```sh
cargo install --path tools/skua-helper --root ~/.local    # from the repository's top folder
```

That puts `skua-helper` in `~/.local/bin`. The bar looks for it once when it starts, so restart the
bar after installing it the first time. After a `git pull` that changes the helper, run the same
command again: the bar compares the version the helper reports with the one in this folder's
`Cargo.toml` and says when the installed one is older. To remove it: `rm ~/.local/bin/skua-helper`.

## How the bar talks to it

One JSON object per line, both ways: lines to the bar (stdout) carry an `"event"`, lines from the
bar (stdin) are commands. The first line of every job is
`{"event":"hello","job":"bluetooth","version":"0.1.3"}`. A problem the job carries on after is
`{"event":"error","message":"..."}`; stderr is only for crashes. The bar writes error messages to
its log, so a message names a command it could not use by its keys and never quotes what the
command held (a copied text, a pairing code). When the bar quits, reloads or no
longer wants a job, the job's stdin closes and it ends. The details are in `src/protocol.rs`; each
job's own lines are described at the top of its file. On the bar's side, `singletons/HelperJob.qml`
runs a job and starts it again if it stops (after 5 s, then 30 s, then every 5 minutes).

## Bluetooth pairing

When a pairing needs a person, BlueZ asks its *pairing agent*. Quickshell has none, so the bar runs
`skua-helper bluetooth`: it registers with BlueZ as the default agent and passes every question to
the bar (`singletons/BluetoothAgent.qml`), which shows it in a window under the bar
(`components/BluetoothPrompt.qml`) and sends your answer back. Anything but a clear yes refuses: an
answer without a value, an empty PIN, or no answer within the minute BlueZ waits. When the job ends,
BlueZ forgets the agent. Without it, only devices that pair without a code can be paired from the
bar.

What BlueZ does with an agent:

- It asks the agent of the program that started the pairing, and the default agent when that
  program has none. Quickshell has none, so this one is asked.
- It keeps the adapter pairable while any agent is registered (unless `AlwaysPairable` is set in
  `/etc/bluetooth/main.conf`). Without an agent, a mouse or a game controller pairs but is not
  remembered.
- A pairing you start with a device that has no screen or keys ("just works") goes through without a
  question. One that a device starts always asks.
- If another agent registers as the default after this one (blueman, for example), BlueZ asks that
  one instead.

## Night light

While night light is on, the bar runs `skua-helper night-light` (`singletons/NightLight.qml`) and
sends it `{"temperature":4000}`. The job asks the compositor for each screen's gamma control (the
`wlr-gamma-control` protocol, which niri and Hyprland offer), screens plugged in later too, and sets
each screen's colour ramps to that temperature. After that and after every change it writes one
line saying, for each screen by name, whether it is `applied`, `refused` or `waiting`. Turning night
light off ends the job, and the compositor gives every screen its own colours back as soon as the
job's gamma controls are gone.

- Only one program at a time can set a screen's colours. If wlsunset, gammastep or another
  gamma-control night light already holds a screen, that screen is `refused`; the quick-settings
  tile says "No gamma control" when every screen is. hyprsunset is different: it tints through
  Hyprland's own colour-matrix protocol, so it is not refused and both tints add up. Turn it off.
- The colours are wlsunset 0.4.0's, computed the same way (`src/gamma.rs`), so 4000 K looks the
  same as it did with wlsunset. The tests in that file compare every value with numbers from
  wlsunset's own C code.
- A compositor without the gamma-control protocol gets an error line and exit code 3.

Gamma cannot be read back over Wayland, so the colours on a real screen are checked by eye.

## Clipboard history

An app only sees the clipboard while one of its windows has the keyboard, so the bar runs
`skua-helper clipboard` (`singletons/ClipboardHistory.qml`). It watches the clipboard through the
compositor's *data-control* protocol (`ext_data_control_manager_v1`, or the older
`zwlr_data_control_manager_v1`; niri and Hyprland have both) and keeps what is copied:

- plain text when the app offers it, otherwise a PNG, JPEG, WebP or GIF image; anything else is
  left out, and so is "an image" whose first bytes are not one of those four formats;
- not a password that a password manager marks secret (the `x-kde-passwordManagerHint` type, which
  `wl-copy --sensitive` sets too), not text over 1 MB or an image over 20 MB, not content an app takes
  over 2 seconds to hand over, and nothing at all while paused;
- at most 500 entries and 500 MB: a new one beyond that deletes the oldest, and copying something
  already kept moves it to the top;
- at most 30 new entries in a burst, then one more every 2 seconds, so an app that sets the
  clipboard in a loop cannot push the whole history out. Copying by hand never reaches this.

The history is in `~/.local/state/skua/clipboard` (`$XDG_STATE_HOME/skua/clipboard`): an
`index.json` and one file per entry, readable only by you (folder 0700, files 0600). That path has
to be a real folder of yours: the job refuses a link in its place. It is kept as
plain files, like cliphist's: the secret hint and the size limits keep things out, and in the
launcher Shift+Delete removes an entry and the last rows of the list pause the history or clear it
(clearing asks for a second Enter). When the launcher puts an entry back on the clipboard, this job
holds it and answers every paste itself, so `wl-copy` is not needed: up to 32 pastes at a time,
each given up when its app takes nothing for 10 seconds or is not done after a minute. Like
anything on a Wayland clipboard, it is gone when the program holding it ends: a bar restart empties
a clipboard the history had filled.

The first time it runs, the bar asks it to import the newest 500 entries of an existing cliphist
history (`cliphist list` and `cliphist decode`, so cliphist must still be installed then); it
remembers that it did, also when there was nothing to import. An entry over the size limits is left
out, and a cliphist that does not answer within 10 seconds ends the import, which is then tried
again the next time the bar starts. `SKUA_CLIPHIST_DB=/path/to/db` imports
from another cliphist database (passed to cliphist as `-db-path`). A compositor without data
control gets an error line, and the job ends with status 3.

The job's lines are described at the top of `src/clipboard/mod.rs`.

## Checking a change

`cargo test`, `cargo clippy -- -D warnings` and `cargo fmt --check`. Bump `version` in `Cargo.toml`
whenever the helper changes, so the bar asks for a reinstall when one built before the change runs.

For the Bluetooth job without a real device, a stand-in BlueZ service on a private D-Bus bus (passed
to the job as `DBUS_SYSTEM_BUS_ADDRESS`) can call the agent's `org.bluez.Agent1` methods
(`RequestPinCode`, `RequestPasskey`, `RequestConfirmation`, `RequestAuthorization`,
`AuthorizeService`) directly, so each kind of question can be checked without pairing anything.

`tests/clipboard.rs` runs the clipboard job against a stand-in compositor: a small Wayland server,
reached through `WAYLAND_SOCKET`, that offers data control and plays the apps that copy and paste
(text, an image, a secret, something that only claims to be an image, a flood of copies, a slow
app, a slow paste, too many pastes, a restart, the wlroots protocol, none at all, the cliphist
import). It never touches your own session or clipboard.
