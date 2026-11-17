# tools/skua-helper

`skua-helper` is Skua's helper program: the jobs a Quickshell bar cannot do in QML because they need
a small program running in the background. Each job is a subcommand, and the bar runs each one as a
process of its own, so one job failing never stops another.

| Job | What it does |
|---|---|
| `skua-helper bluetooth` | answers BlueZ's pairing questions (a PIN, a passkey, "does the device show 123456?") through the bar |

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
`{"event":"hello","job":"bluetooth","version":"0.1.0"}`. A problem the job carries on after is
`{"event":"error","message":"..."}`; stderr is only for crashes. When the bar quits, reloads or no
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

## Checking a change

`cargo test`, `cargo clippy -- -D warnings` and `cargo fmt --check`. When a job's lines change, bump
`version` in `Cargo.toml`, so a helper built before the change is noticed.

For the Bluetooth job without a real device, a stand-in BlueZ service on a private D-Bus bus (passed
to the job as `DBUS_SYSTEM_BUS_ADDRESS`) can call the agent's `org.bluez.Agent1` methods
(`RequestPinCode`, `RequestPasskey`, `RequestConfirmation`, `RequestAuthorization`,
`AuthorizeService`) directly, so each kind of question can be checked without pairing anything.
