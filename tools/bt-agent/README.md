# tools/bt-agent

`tern-bar-bt-agent`, the Bluetooth pairing helper. When a pairing needs a person (a PIN to type, a
passkey, "does the device show 123456?", "may this device pair or connect?"), BlueZ asks its
*pairing agent*. Quickshell has none, so tern-bar starts this small program: it registers with
BlueZ as the default agent and passes every question to the bar, which shows it in a window under
the bar and sends your answer back.

```sh
cargo install --path tools/bt-agent --root ~/.local    # from the repository's top folder
```

That puts `tern-bar-bt-agent` in `~/.local/bin`. The bar looks for it once when it starts, so
restart the bar after installing it. To remove it: `rm ~/.local/bin/tern-bar-bt-agent`. Without it,
only devices that pair without a code can be paired from the bar.

## How the bar talks to it

One JSON object per line, both ways: questions on the program's stdout, answers on its stdin. The
format is at the top of `src/main.rs`; the bar's side is `singletons/BluetoothAgent.qml` (running
the program, restarting it if it stops) and `components/BluetoothPrompt.qml` (the window). Anything
but a clear yes refuses: an answer without a value, an empty PIN, or no answer within the minute
BlueZ waits. When the bar quits or reloads, the program's stdin closes, it exits, and BlueZ forgets
the agent.

## What BlueZ does with an agent

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

`cargo clippy -- -D warnings` and `cargo fmt --check`. For a real test without a real device, the
probe rig has a fake BlueZ that asks every kind of question:
`~/.claude/skills/audit-toolkit/quickshell-probe/examples/fake_bluez.py`.
