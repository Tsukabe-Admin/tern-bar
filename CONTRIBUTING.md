# Contributing

This is a hobby project and a vibecoding experiment, not a product with a support team. Small,
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
`quickshell kill -c tern-bar` and start it again (the README has the exact command and the
`NIRI_SOCKET` note).

## Sending a change

- Test it on a real bar, not only by reading the diff. Most problems here (blur, layout,
  visibility) only show up on screen.
- Mention what you tested and on which Quickshell version.
- Match the existing style: plain QML, comments that explain *why*, and no hardcoded home paths.
- New text labels need `textFormat: Text.PlainText` — window titles, clipboard entries, SSIDs and
  media metadata are untrusted, and Qt would otherwise parse them as rich text.
- Runtime files belong in `~/.config/tern-bar/` and `~/.local/state/tern-bar/`, never in the repo.
- Keep the README in sync when behaviour or options change.

If a change is large or you are unsure where to start, open an issue first and we can shape it
together. No question is too basic; I am learning too.

## Ideas and help

Feature ideas, design mockups, screenshots of your own bar and offers to help with other projects
are all welcome. Open an issue and say hello.
