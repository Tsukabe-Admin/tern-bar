pragma Singleton

import QtQuick
import Quickshell

// The one door to the compositor: workspaces, windows, keyboard layouts and the
// focus/quit actions, whichever compositor this bar runs on. Every component
// talks to this singleton, never to Niri directly. Each forward reads only the
// branch that applies, so the Niri singleton (and its socket) is never created
// on Hyprland.
Singleton {
    id: root

    // "hyprland" when this bar's Wayland display is a Hyprland instance, else "niri"
    // (also when neither runs: the niri side is then inert, as before).
    readonly property string kind: {
        const sig = String(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "");
        const niri = String(Quickshell.env("NIRI_SOCKET") || "");
        const display = String(Quickshell.env("WAYLAND_DISPLAY") || "wayland-0").split("/").pop();
        // niri names its socket niri.<display>.<pid>.sock. One for another display is
        // the outer session of a nested Hyprland; a leftover Hyprland signature on a
        // real niri session does not win over niri's own socket.
        const niriIsOurs = niri !== "" && niri.split("/").pop().indexOf("niri." + display + ".") === 0;
        return (sig !== "" && !niriIsOurs) ? "hyprland" : "niri";
    }
    readonly property bool isNiri: root.kind === "niri"
    readonly property bool isHyprland: root.kind === "hyprland"
    // The Hyprland side (singletons/HyprlandBackend.qml), loaded only on Hyprland.
    readonly property var hy: hyprLoader.item

    LazyLoader {
        id: hyprLoader
        active: root.isHyprland
        source: Qt.resolvedUrl("HyprlandBackend.qml")
    }

    // True once the compositor's state is coming in; false before that, or when
    // the bar was started outside a compositor it knows.
    readonly property bool connected: root.isHyprland ? root.hy !== null : Niri.connected
    // Every window: { id, title, app_id, workspace_id, is_focused, ... }.
    readonly property var windows: root.isHyprland ? (root.hy ? root.hy.windows : []) : Niri.windows
    readonly property var keyboardLayouts: root.isHyprland ? (root.hy ? root.hy.keyboardLayouts : []) : Niri.keyboardLayouts
    readonly property string shortKeyboardLayout: root.isHyprland ? (root.hy ? root.hy.shortKeyboardLayout : "") : Niri.shortKeyboardLayout

    // One output's workspaces in order: { id, idx, name, is_active, is_focused, is_urgent, active_window_id }.
    function workspacesFor(output) {
        return root.isHyprland ? (root.hy ? root.hy.workspacesFor(output) : []) : Niri.workspacesFor(output);
    }

    // The focused window if it is on `output`, else null.
    function focusedWindowOn(output) {
        return root.isHyprland ? (root.hy ? root.hy.focusedWindowOn(output) : null) : Niri.focusedWindowOn(output);
    }

    // The output holding the focused workspace, or "" before the compositor has said.
    function focusedOutput() {
        return root.isHyprland ? (root.hy ? root.hy.focusedOutput() : "") : Niri.focusedOutput();
    }

    function focusWorkspace(id) {
        if (root.isHyprland) {
            if (root.hy)
                root.hy.focusWorkspace(id);
        } else {
            Niri.focusWorkspace(id);
        }
    }

    // Focus an output by name, so a launch lands on the screen whose pill was
    // clicked (the compositor opens new windows on the focused output).
    function focusMonitor(output) {
        if (root.isHyprland) {
            if (root.hy)
                root.hy.focusMonitor(output);
        } else {
            Niri.focusMonitor(output);
        }
    }

    function focusWindow(id) {
        if (root.isHyprland) {
            if (root.hy)
                root.hy.focusWindow(id);
        } else {
            Niri.focusWindow(id);
        }
    }

    function switchLayoutNext() {
        if (root.isHyprland) {
            if (root.hy)
                root.hy.switchLayoutNext();
        } else {
            Niri.switchLayoutNext();
        }
    }

    function switchLayoutPrev() {
        if (root.isHyprland) {
            if (root.hy)
                root.hy.switchLayoutPrev();
        } else {
            Niri.switchLayoutPrev();
        }
    }

    // Log out, without the compositor's own confirmation (the launcher asks).
    function quit() {
        if (root.isHyprland) {
            if (root.hy)
                root.hy.quit();
        } else {
            Niri.quit();
        }
    }

    // niri's own "Important Hotkeys" overlay (the tools pill's ? button, niri only).
    function showHotkeyOverlay() {
        if (root.isNiri)
            Niri.showHotkeyOverlay();
    }
}
