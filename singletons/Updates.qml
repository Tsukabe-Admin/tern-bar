pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Pending system package updates (Arch/Pacman + AUR when paru or yay is present).
// Polled once for the whole shell while the updates pill is not hidden, and
// cached in $XDG_STATE_HOME/tern-bar/updates.json so a restart shows the last
// known count immediately while checkupdates refreshes in the background.
Singleton {
    id: root

    readonly property bool supported:
        Programs.has("checkupdates") || Programs.has("pacman")

    property int count: 0
    readonly property bool available: root.supported && root.count > 0

    readonly property bool wanted:
        BarConfig.configLoaded && BarConfig.hidden.indexOf("updates") === -1 && root.supported

    property bool recheck: false

    function refresh() {
        if (!root.supported)
            return;
        if (checker.running)
            root.recheck = true;
        else
            checker.running = true;
    }

    // Launch an interactive terminal running the system upgrade, then re-check
    // as soon as the terminal closes.
    function runUpdate() {
        if (updater.running || Programs.terminal === "")
            return;
        const cmd = Programs.terminalCommand(["sh", "-c",
            "if command -v paru >/dev/null 2>&1; then paru -Syu; "
            + "elif command -v yay >/dev/null 2>&1; then yay -Syu; "
            + "else sudo pacman -Syu; fi"]);
        updater.command = cmd;
        Qt.callLater(() => { updater.running = true; });
    }

    FileView {
        id: cacheFile
        path: BarConfig.stateDir + "/updates.json"
        blockLoading: true
        printErrors: false
    }

    Process {
        id: checker
        command: ["sh", "-c",
            "state=\"${XDG_STATE_HOME:-$HOME/.local/state}/tern-bar\"; "
            + "mkdir -p \"$state\"; "
            + "if [ -n \"${TERN_BAR_UPDATES_MOCK:-}\" ]; then "
            + "  total=$TERN_BAR_UPDATES_MOCK; "
            + "else "
            + "  repo=0; aur=0; "
            + "  cu_cmd=\"${TERN_BAR_CHECKUPDATES_CMD:-checkupdates}\"; "
            + "  if command -v \"$cu_cmd\" >/dev/null 2>&1; then "
            + "    rc=0; out=$(\"$cu_cmd\" 2>/dev/null) || rc=$?; "
            + "    if [ \"$rc\" -eq 0 ]; then "
            + "      repo=$(printf '%s\\n' \"$out\" | grep -c . || true); "
            + "    elif [ \"$rc\" -eq 2 ]; then "
            + "      repo=0; "
            + "    else "
            + "      exit 1; "
            + "    fi; "
            + "  elif command -v pacman >/dev/null 2>&1; then "
            + "    rc=0; out=$(pacman -Qu 2>/dev/null) || rc=$?; "
            + "    if [ \"$rc\" -eq 0 ]; then "
            + "      repo=$(printf '%s\\n' \"$out\" | grep -c . || true); "
            + "    elif [ \"$rc\" -eq 1 ]; then "
            + "      repo=0; "
            + "    else "
            + "      exit 1; "
            + "    fi; "
            + "  fi; "
            + "  if command -v paru >/dev/null 2>&1; then "
            + "    aur=$(paru -Qua 2>/dev/null | wc -l); "
            + "  elif command -v yay >/dev/null 2>&1; then "
            + "    aur=$(yay -Qua 2>/dev/null | wc -l); "
            + "  fi; "
            + "  total=$(( repo + aur )); "
            + "  printf '{\"count\": %d}\\n' \"$total\" > \"$state/updates.json.tmp\" "
            + "  && mv \"$state/updates.json.tmp\" \"$state/updates.json\"; "
            + "fi; "
            + "printf '%d\\n' \"$total\""]
        stdout: SplitParser {
            onRead: (line) => {
                const n = parseInt(line.trim(), 10);
                if (!isNaN(n) && n >= 0)
                    root.count = n;
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.recheck) {
                root.recheck = false;
                checker.running = true;
            } else if (exitCode !== 0 && root.wanted) {
                retryTimer.restart();
            }
        }
    }

    Process {
        id: updater
        onExited: root.refresh()
    }

    Timer {
        interval: 1800000
        repeat: true
        running: root.wanted
        onTriggered: root.refresh()
    }

    Timer {
        id: retryTimer
        interval: 60000
        onTriggered: {
            if (root.wanted)
                root.refresh();
        }
    }

    onWantedChanged: {
        if (root.wanted)
            root.refresh();
    }

    Component.onCompleted: {
        try {
            const o = JSON.parse(cacheFile.text());
            if (o && typeof o.count === "number" && o.count >= 0)
                root.count = Math.floor(o.count);
        } catch (e) {
        }
        if (root.wanted)
            root.refresh();
    }
}
