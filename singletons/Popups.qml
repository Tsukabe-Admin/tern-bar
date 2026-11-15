pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Which of the bar's popups is open — "calendar", "quick" (quick settings),
// "media", "notifications" (the notification centre) or "" — and on which
// screen. One at a time: opening one closes the others and the launcher. Each
// bar shows a popup only when `screenName` is its own screen.
Singleton {
    id: root

    property string open: ""
    property string screenName: ""
    // Selected MPRIS player's dbusName when multiple players are active.
    property string preferredPlayer: ""
    // Active bottom-docked OSD spans by key ("volume" / "brightness") -> { screenName, spanWidth }.
    property var osdDocks: ({})

    function reportOsdDock(key, screenName, active, spanWidth) {
        const prev = root.osdDocks || {};
        const next = Object.assign({}, prev);
        if (active && screenName !== "" && spanWidth > 0) {
            const existing = prev[key];
            if (existing && existing.screenName === screenName && existing.spanWidth === spanWidth)
                return;
            next[key] = { screenName: screenName, spanWidth: spanWidth };
        } else {
            if (!(key in prev))
                return;
            delete next[key];
        }
        root.osdDocks = next;
    }

    function osdDockSpan(screenName) {
        if (!screenName)
            return 0;
        let maxSpan = 0;
        const docks = root.osdDocks || {};
        const keys = Object.keys(docks);
        for (let i = 0; i < keys.length; i++) {
            const d = docks[keys[i]];
            if (d && d.screenName === screenName && d.spanWidth > maxSpan)
                maxSpan = d.spanWidth;
        }
        return maxSpan;
    }

    function pickPlayer(players) {
        if (!players || players.length === 0)
            return null;
        if (root.preferredPlayer !== "") {
            for (let i = 0; i < players.length; i++) {
                if (players[i] && players[i].dbusName === root.preferredPlayer)
                    return players[i];
            }
        }
        let first = null;
        for (let i = 0; i < players.length; i++) {
            const p = players[i];
            if (!first)
                first = p;
            if (p && p.isPlaying)
                return p;
        }
        return first;
    }

    function toggle(name, screenName) {
        if (root.open === name && root.screenName === screenName) {
            root.open = "";
            return;
        }
        // The media card only shows while there is a player. Asked for without
        // one (over IPC; the pill is hidden then), "media" would be open with
        // nothing to see, and the card would appear by itself whenever a player
        // started.
        if (name === "media" && root.pickPlayer(Mpris.players.values || []) === null)
            return;
        // The same under a fullscreen window (a keybind still works there):
        // the bar and its popups are hidden beneath it, so the popup would be
        // open unseen and show up when the window left fullscreen.
        if (Compositor.isOutputFullscreen(screenName))
            return;
        if (Launcher.open)
            Launcher.close();
        root.screenName = screenName;
        root.open = name;
    }

    function close() {
        root.open = "";
    }

    Connections {
        target: BarConfig
        function onLookChanged() {
            root.close();
        }
    }

    Connections {
        target: Compositor
        function onFullscreenChanged(output, isFullscreen) {
            if (isFullscreen && root.open !== "" && root.screenName === output)
                root.close();
        }
    }

    // A screen object by output name; the first screen if there is no such name.
    function screenNamed(name) {
        const list = Quickshell.screens;
        for (let i = 0; i < list.length; i++) {
            if (list[i].name === name)
                return list[i];
        }
        return list.length > 0 ? list[0] : null;
    }

    // The output the compositor has focused, else the first screen's name.
    function focusedScreenName() {
        const name = Compositor.focusedOutput();
        if (name !== "")
            return name;
        const list = Quickshell.screens;
        return list.length > 0 ? list[0].name : "";
    }
}
