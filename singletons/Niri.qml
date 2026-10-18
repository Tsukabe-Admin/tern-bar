pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// niri 26.04 IPC client: subscribes to the event stream over $NIRI_SOCKET and
// exposes workspaces/windows plus a focus-by-Id action. Everything here is
// event-driven; we never shell out to `niri msg` (that CLI cannot address
// workspaces by Id, and both outputs have an index 1).
Singleton {
    id: root

    property string socketPath: String(Quickshell.env("NIRI_SOCKET") || "")
    property var workspaces: []
    property var windows: []
    property int focusedWindowId: -1
    property var keyboardLayouts: []
    property int keyboardLayoutIdx: 0

    readonly property string currentKeyboardLayout:
        (root.keyboardLayoutIdx >= 0 && root.keyboardLayoutIdx < root.keyboardLayouts.length)
            ? String(root.keyboardLayouts[root.keyboardLayoutIdx] || "") : ""
    readonly property string shortKeyboardLayout: root.abbreviateLayout(root.currentKeyboardLayout)

    readonly property alias connected: socket.connected

    function abbreviateLayout(name) {
        const s = String(name || "").trim();
        if (s === "")
            return "";
        const paren = /\(([^)]+)\)/.exec(s);
        if (paren) {
            const inner = paren[1].trim();
            if (/^[A-Za-z]{2,3}$/.test(inner))
                return inner.toUpperCase();
            const codePrefix = /^([A-Z]{2,3})(?:[,;\s]|$)/.exec(inner);
            if (codePrefix)
                return codePrefix[1];
            const lowerInner = inner.toLowerCase();
            if (lowerInner.indexOf("dvorak") !== -1)
                return "DV";
            if (lowerInner.indexOf("colemak") !== -1)
                return "CM";
            if (lowerInner.indexOf("workman") !== -1)
                return "WM";
            if (lowerInner.indexOf("brazil") !== -1)
                return "BR";
            if (lowerInner.indexOf("canada") !== -1)
                return "CA";
            if (lowerInner.indexOf("austral") !== -1)
                return "AU";
            if (lowerInner.indexOf("latin") !== -1)
                return "LA";
        }
        const map = {
            english: "US", japanese: "JP", russian: "RU", german: "DE", french: "FR",
            spanish: "ES", italian: "IT", portuguese: "PT", korean: "KR", chinese: "CN",
            arabic: "AR", hebrew: "IL", ukrainian: "UA", polish: "PL", dutch: "NL",
            swedish: "SE", norwegian: "NO", danish: "DK", finnish: "FI", turkish: "TR",
            czech: "CZ", greek: "GR", vietnamese: "VN", thai: "TH", hindi: "IN"
        };
        const firstWord = s.split(/[\s(]+/)[0].toLowerCase();
        if (firstWord in map)
            return map[firstWord];
        return s.slice(0, 2).toUpperCase();
    }

    function handle(line) {
        var obj;
        try {
            obj = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (!obj)
            return;

        if (obj.WorkspacesChanged) {
            root.workspaces = obj.WorkspacesChanged.workspaces || [];
        } else if (obj.WorkspaceActivated) {
            // niri emits one event for the newly active workspace only: the
            // old active workspace on that output must be cleared here, and a
            // focused activation also unfocuses every other workspace (niri
            // does not emit an event for the previous output's workspace).
            var ev = obj.WorkspaceActivated;
            var out = null;
            for (var i = 0; i < root.workspaces.length; i++) {
                if (root.workspaces[i].id === ev.id) {
                    out = root.workspaces[i].output;
                    break;
                }
            }
            if (out === null)
                return;
            var next = [];
            for (var j = 0; j < root.workspaces.length; j++) {
                var ws = root.workspaces[j];
                var active = ws.is_active;
                var focused = ws.is_focused;
                if (ws.output === out)
                    active = ws.id === ev.id;
                if (ev.focused)
                    focused = ws.id === ev.id;
                if (active === ws.is_active && focused === ws.is_focused)
                    next.push(ws);
                else
                    next.push(Object.assign({}, ws, { is_active: active, is_focused: focused }));
            }
            root.workspaces = next;
        } else if (obj.WindowsChanged) {
            // The initial stream has no WindowFocusChanged: the focused window
            // is only marked by is_focused in this full snapshot.
            root.windows = obj.WindowsChanged.windows || [];
            root.focusedWindowId = -1;
            for (var f = 0; f < root.windows.length; f++) {
                if (root.windows[f].is_focused) {
                    root.focusedWindowId = root.windows[f].id;
                    break;
                }
            }
        } else if (obj.WindowFocusChanged) {
            var fid = obj.WindowFocusChanged.id;
            root.focusedWindowId = (fid === null || fid === undefined) ? -1 : fid;
            var patched = [];
            for (var k = 0; k < root.windows.length; k++) {
                var w = root.windows[k];
                var isF = w.id === root.focusedWindowId;
                if (w.is_focused === isF)
                    patched.push(w);
                else
                    patched.push(Object.assign({}, w, { is_focused: isF }));
            }
            root.windows = patched;
        } else if (obj.WindowOpenedOrChanged) {
            var nw = obj.WindowOpenedOrChanged.window;
            if (!nw)
                return;
            var arr = root.windows.slice();
            var found = false;
            for (var m = 0; m < arr.length; m++) {
                if (arr[m].id === nw.id) {
                    arr[m] = nw;
                    found = true;
                    break;
                }
            }
            if (!found)
                arr.push(nw);
            root.windows = arr;
            // A newly focused window implies every other one lost focus.
            if (nw.is_focused)
                root.focusedWindowId = nw.id;
        } else if (obj.WindowClosed) {
            var cid = obj.WindowClosed.id;
            var kept = [];
            for (var n = 0; n < root.windows.length; n++) {
                if (root.windows[n].id !== cid)
                    kept.push(root.windows[n]);
            }
            root.windows = kept;
            if (root.focusedWindowId === cid)
                root.focusedWindowId = -1;
        } else if (obj.KeyboardLayoutsChanged) {
            var kl = obj.KeyboardLayoutsChanged.keyboard_layouts;
            if (kl) {
                root.keyboardLayouts = kl.names || [];
                root.keyboardLayoutIdx = typeof kl.current_idx === "number" ? kl.current_idx : 0;
            }
        } else if (obj.KeyboardLayoutSwitched) {
            var kidx = obj.KeyboardLayoutSwitched.idx;
            if (typeof kidx === "number")
                root.keyboardLayoutIdx = kidx;
        }
    }

    function workspacesFor(outputName) {
        var out = [];
        for (var i = 0; i < root.workspaces.length; i++) {
            if (root.workspaces[i].output === outputName)
                out.push(root.workspaces[i]);
        }
        out.sort(function(a, b) { return a.idx - b.idx; });
        return out;
    }

    function workspaceById(id) {
        for (var i = 0; i < root.workspaces.length; i++) {
            if (root.workspaces[i].id === id)
                return root.workspaces[i];
        }
        return null;
    }

    function focusedWindowOn(outputName) {
        for (var i = 0; i < root.windows.length; i++) {
            var w = root.windows[i];
            if (w.id !== root.focusedWindowId)
                continue;
            var ws = root.workspaceById(w.workspace_id);
            if (ws && ws.output === outputName)
                return w;
        }
        return null;
    }

    function focusWorkspace(id) {
        sendAction({ Action: { FocusWorkspace: { reference: { Id: id } } } });
    }

    // Focus an output by name, so a launch lands on the screen whose pill was
    // clicked (niri opens new windows on the focused output).
    function focusMonitor(outputName) {
        sendAction({ Action: { FocusMonitor: { output: outputName } } });
    }

    // The tools pill's ? button: niri's own "Important Hotkeys" overlay.
    function showHotkeyOverlay() {
        sendAction({ Action: { ShowHotkeyOverlay: {} } });
    }

    // Cycle active keyboard layout via niri IPC.
    function switchLayoutNext() {
        sendAction({ Action: { SwitchLayout: { layout: "Next" } } });
    }

    function switchLayoutPrev() {
        sendAction({ Action: { SwitchLayout: { layout: "Prev" } } });
    }

    // The output holding the focused workspace, or "" before niri has said.
    function focusedOutput() {
        for (var i = 0; i < root.workspaces.length; i++) {
            if (root.workspaces[i].is_focused)
                return root.workspaces[i].output || "";
        }
        return "";
    }

    function focusWindow(id) {
        sendAction({ Action: { FocusWindow: { id: id } } });
    }

    // Log out: niri's quit, without its own confirmation (the launcher asks).
    function quit() {
        sendAction({ Action: { Quit: { skip_confirmation: true } } });
    }

    // niri ignores Actions written to the event-stream socket (verified: no
    // reply, no state change), so actions go on their own short-lived
    // connection, mirroring what `niri msg action` does internally.
    property var pendingActions: []

    function sendAction(payload) {
        if (actionSocket.connected) {
            actionSocket.write(JSON.stringify(payload) + "\n");
            actionTimer.restart();
            return;
        }
        root.pendingActions.push(payload);
        actionSocket.connected = true;
    }

    Socket {
        id: actionSocket
        path: root.socketPath
        onConnectionStateChanged: {
            if (actionSocket.connected && root.pendingActions.length > 0) {
                const queue = root.pendingActions.slice();
                root.pendingActions = [];
                for (let i = 0; i < queue.length; i++)
                    actionSocket.write(JSON.stringify(queue[i]) + "\n");
                actionTimer.restart();
            }
        }
    }

    Timer {
        id: actionTimer
        interval: 150
        onTriggered: actionSocket.connected = false
    }

    Socket {
        id: socket
        path: root.socketPath
        parser: SplitParser {
            onRead: (line) => root.handle(line)
        }
        onConnectionStateChanged: {
            if (socket.connected) {
                reconnectTimer.stop();
                socket.write("\"EventStream\"\n");
            } else if (socket.path !== "") {
                reconnectTimer.restart();
            }
        }
        onError: (error) => {
            if (socket.path !== "")
                reconnectTimer.restart();
        }
    }

    Timer {
        id: reconnectTimer
        interval: 1000
        onTriggered: socket.connected = true
    }

    Component.onCompleted: {
        if (socket.path !== "")
            socket.connected = true;
    }
}
