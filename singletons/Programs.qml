pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Which optional programs this computer has, looked up once at start.
// Features that need a missing program hide themselves or say what to install.
Singleton {
    id: root

    // program name → true, for: wlsunset blueman-manager cliphist wl-copy
    // swaylock, plus the pseudo-name "power-profiles" (the D-Bus service).
    property var found: ({})
    // The terminal for desktop entries with Terminal=true: $TERMINAL, else the
    // first one installed of xdg-terminal-exec kitty foot alacritty ghostty wezterm.
    property string terminal: String(Quickshell.env("TERMINAL") || "")

    function has(name) {
        return root.found[name] === true;
    }

    // The command that runs `command` (a list) inside the terminal.
    function terminalCommand(command) {
        const term = root.terminal;
        const base = term.slice(term.lastIndexOf("/") + 1);
        const prefixes = {
            "xdg-terminal-exec": [], kitty: [], foot: [],
            alacritty: ["-e"], ghostty: ["-e"], wezterm: ["start", "--"]
        };
        const prefix = (base in prefixes) ? prefixes[base] : ["-e"];
        return [term].concat(prefix, Array.from(command));
    }

    Process {
        id: probe
        command: ["sh", "-c",
            "for p in wlsunset blueman-manager cliphist wl-copy swaylock; do "
            + "command -v \"$p\" >/dev/null 2>&1 && echo \"have $p\"; done; "
            + "for t in xdg-terminal-exec kitty foot alacritty ghostty wezterm; do "
            + "command -v \"$t\" >/dev/null 2>&1 && { echo \"term $t\"; break; }; done; "
            + "{ busctl --system status net.hadess.PowerProfiles || "
            + "busctl --system status org.freedesktop.UPower.PowerProfiles; } >/dev/null 2>&1 "
            + "&& echo 'have power-profiles'; true"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("have ") === 0) {
                    const next = Object.assign({}, root.found);
                    next[line.slice(5).trim()] = true;
                    root.found = next;
                } else if (line.indexOf("term ") === 0 && root.terminal === "") {
                    root.terminal = line.slice(5).trim();
                }
            }
        }
    }

    Component.onCompleted: probe.running = true
}
