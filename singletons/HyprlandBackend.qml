import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "keyboard.js" as Keyboard

// Hyprland's side of Compositor: the same properties and actions Niri offers,
// in the same shapes, built from Quickshell's Hyprland module. Compositor loads
// this file only on Hyprland, so on niri the Hyprland connection is never made
// (and never logs). It is the only file that imports Quickshell.Hyprland.
Scope {
    id: root

    // Hyprland 0.55+ with a hyprland.lua config takes dispatchers as Lua; with a
    // hyprland.conf it takes the classic words. Each action gives both.
    function dispatch(lua, legacy) {
        Hyprland.dispatch(Hyprland.usingLua ? lua : legacy);
    }

    function luaString(s) {
        return '"' + String(s).replace(/[\\"]/g, "\\$&") + '"';
    }

    // A window in niri's shape. The id is the window's address as a number
    // (user-space addresses fit in a double exactly), so code that compares ids
    // or passes one back to focusWindow works unchanged.
    function windowOf(t) {
        return {
            id: parseInt(t.address, 16),
            title: t.title,
            app_id: (t.wayland && t.wayland.appId) || (t.lastIpcObject && t.lastIpcObject.class) || "",
            workspace_id: t.workspace ? t.workspace.id : -1,
            output: t.monitor ? t.monitor.name : "",
            is_focused: t.activated
        };
    }

    readonly property var windows: Hyprland.toplevels.values.map(root.windowOf)

    // One monitor's workspaces in niri's shape: numbered ones in order, then
    // named ones. Special workspaces (scratchpads) are not chips.
    function workspacesFor(output) {
        return Hyprland.workspaces.values
            .filter((w) => w.monitor && w.monitor.name === output && !String(w.name).startsWith("special:"))
            .sort((a, b) => ((a.id < 0) - (b.id < 0)) || (a.id - b.id))
            .map((w, i) => ({
                id: w.id, idx: i + 1, name: w.name, output: output,
                is_active: w.active, is_focused: w.focused, is_urgent: w.urgent,
                active_window_id: w.toplevels.values.length > 0 ? 1 : null
            }));
    }

    function focusedWindowOn(output) {
        const t = Hyprland.activeToplevel;
        return (t && t.monitor && t.monitor.name === output) ? root.windowOf(t) : null;
    }

    function focusedOutput() {
        return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
    }

    function focusWorkspace(id) {
        const w = Hyprland.workspaces.values.find((x) => x.id === id);
        if (w)
            w.activate();
    }

    function focusMonitor(output) {
        root.dispatch("hl.dsp.focus({ monitor = " + root.luaString(output) + " })", "focusmonitor " + output);
    }

    function focusWindow(id) {
        const a = "address:0x" + id.toString(16);
        root.dispatch("hl.dsp.focus({ window = " + root.luaString(a) + " })", "focuswindow " + a);
    }

    // hyprshutdown closes the apps first when it is installed (Hyprland's own
    // Log out does the same); otherwise Hyprland exits directly.
    function quit() {
        if (Programs.has("hyprshutdown"))
            Quickshell.execDetached(["hyprshutdown"]);
        else
            root.dispatch("hl.dsp.exit()", "exit");
    }

    // ── Scratchpads ──────────────────────────────────────────────────────────
    // Monitor name → the special workspace shown on it ("special:magic"), or "".
    // Quickshell does not follow special workspaces, so this reads
    // `hyprctl -j monitors` once and then Hyprland's activespecial events.
    property var specialByMonitor: ({})

    function specialWorkspaceOn(output) {
        const name = String(root.specialByMonitor[output] || "");
        return name.startsWith("special:") ? name.slice(8) : name;
    }

    function toggleSpecialWorkspace(name) {
        root.dispatch("hl.dsp.workspace.toggle_special(" + root.luaString(name) + ")",
                      "togglespecialworkspace " + name);
    }

    Process {
        id: monitors
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            id: monitorsOut
            onStreamFinished: {
                const next = {};
                try {
                    for (const m of JSON.parse(monitorsOut.text))
                        next[m.name] = (m.specialWorkspace && m.specialWorkspace.name) || "";
                } catch (e) {
                    return;
                }
                root.specialByMonitor = next;
            }
        }
    }

    // ── Keyboard layouts ─────────────────────────────────────────────────────
    // Read from `hyprctl -j devices` (the main keyboard, else the first), again
    // whenever Hyprland says the layout or its config changed.
    property var keyboardLayouts: []
    property string currentKeyboardLayout: ""
    readonly property string shortKeyboardLayout: Keyboard.abbreviate(root.currentKeyboardLayout)

    function switchLayoutNext() {
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"]);
    }

    function switchLayoutPrev() {
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "prev"]);
    }

    Process {
        id: devices
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            id: devicesOut
            onStreamFinished: {
                let kb = null;
                try {
                    const list = JSON.parse(devicesOut.text).keyboards || [];
                    kb = list.find((k) => k.main) || list[0] || null;
                } catch (e) {
                    kb = null;
                }
                root.keyboardLayouts = kb ? String(kb.layout || "").split(",").filter((s) => s !== "") : [];
                root.currentKeyboardLayout = kb ? String(kb.active_keymap || "") : "";
            }
        }
    }

    Timer {
        id: keyboardRefresh
        interval: 100
        onTriggered: {
            if (devices.running)
                keyboardRefresh.restart();
            else
                devices.running = true;
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            const name = event.name;
            // Quickshell's own openwindow handler leaves out the window class;
            // a refresh fills it in (lastIpcObject.class).
            if (name === "openwindow") {
                Hyprland.refreshToplevels();
            } else if (name === "activelayout" || name === "configreloaded") {
                keyboardRefresh.restart();
            } else if (name === "activespecial") {
                // "NAME,MONITOR"; NAME is empty when the scratchpad was hidden.
                // Split at the last comma: a monitor name has none.
                const data = String(event.data);
                const at = data.lastIndexOf(",");
                if (at === -1)
                    return;
                const next = Object.assign({}, root.specialByMonitor);
                next[data.slice(at + 1)] = data.slice(0, at);
                root.specialByMonitor = next;
            }
        }
    }

    Component.onCompleted: {
        Hyprland.refreshToplevels();
        devices.running = true;
        monitors.running = true;
    }
}
