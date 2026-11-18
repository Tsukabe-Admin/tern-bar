# Contributing

This is a hobby project, not a product with a support team. Small,
focused changes are easiest to review, and ideas are as welcome as code.

## Reporting a bug

Include:

- what you did, what you expected and what happened;
- a screenshot or short recording (a phone photo of the screen is fine);
- your distro, niri and Quickshell versions (`qs --version`);
- the log lines around the problem.

Logs come from the running instance:

```bash
qs list --all                 # find the instance id and PID
qs log -i <instance-id> -t 100
```

QML errors show up as `WARN scene: @file.qml[line:-1]: ...`. If the bar failed to reload after an
edit, it keeps running the old code — restart it with
`quickshell kill -c skua` and start it again (the README has the exact command and the
`NIRI_SOCKET` note).

## Sending a change

- Test it on a real bar, not only by reading the diff. Most problems here (blur, layout,
  visibility) only show up on screen.
- Try it in both looks. `quickshell ipc -c skua call bar cycleLook` switches between Pills and
  Frame while the bar runs; a popup is a floating card in one and a drawer in the other, built
  from the same file in `components/views/`. Pills is the default everyone gets, so a change meant
  for Frame should leave it looking exactly as it did.
- Mention what you tested and on which Quickshell version.
- Every push and pull request runs the checks below on GitHub, from a clean clone
  (`.github/workflows/ci.yml`: an Arch container with the packages of one fixed day), together with
  shellcheck on the scripts, gitleaks on the history and osv-scanner on the dependencies. A red
  cross on a pull request is no reason to hold it back: say so and we will look at it together.
- `node --test tests/` runs the unit tests (plain Node, nothing to install). They cover the script
  libraries in `singletons/`: the launcher's calculator (`calc.js`), the Looks options, the
  ink-on-accent contrast and niri's fullscreen check (`looks.js`), the cleaning of notification
  text (`notifytext.js`), the built-in themes and the bar's palette (`themesync.js`), the weather
  replies (`weather.js`), and the folder picker's path rules (`folderpath.js`). Run them if you
  touch one of those files, and add a case for a rule you add. The QML itself has no tests: that
  is what the real bar is for.
- `/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml -I . shell.qml components/*.qml components/views/*.qml singletons/*.qml`
  must end without an error status (`echo $?` says 0; the path is Arch's, and qmllint comes with
  Qt's declarative tools). It prints a couple of hundred warnings about Quickshell types it cannot
  see; those are expected. What it calls an error is a syntax error or an id used twice.
- `tools/skua-helper` (Rust): `cargo test`, `cargo clippy --all-targets -- -D warnings` and
  `cargo fmt --check` from that folder. Its README says how each job is checked without touching
  your own session, and when to bump its version.
- The Frame look's shadows are two GLSL shaders in `shaders/`. The bar loads the compiled
  `.frag.qsb` files, not the sources, so after editing a `.frag` run `tools/build-shaders.sh` and
  commit both. `tools/build-shaders.sh --check` says whether the compiled files hold what their
  sources give (it compares their contents: the files' bytes differ from one system to the next).
- Match the existing style: plain QML, comments that explain *why*, and no hardcoded home paths.
- New text labels need `textFormat: Text.PlainText` — window titles, clipboard entries, SSIDs and
  media metadata are untrusted, and Qt would otherwise parse them as rich text.
- Runtime files belong in `~/.config/skua/` and `~/.local/state/skua/`, never in the repo.
- Keep the README in sync when behaviour or options change.

If a change is large or you are unsure where to start, open an issue first and we can shape it
together. No question is too basic; I am learning too.

## Ideas and help

Feature ideas, design mockups, screenshots of your own bar and offers to help with other projects
are all welcome. Open an issue and say hello.
