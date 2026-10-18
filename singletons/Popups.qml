pragma Singleton

import QtQuick
import Quickshell

// Which of the bar's popups is open — "calendar", "quick" (quick settings),
// "media" or "" — and on which screen. One at a time: opening one closes the
// others and the launcher. Each bar shows a popup only when `screenName` is its
// own screen.
Singleton {
    id: root

    property string open: ""
    property string screenName: ""
    // Selected MPRIS player's dbusName when multiple players are active.
    property string preferredPlayer: ""

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
        if (Launcher.open)
            Launcher.close();
        root.screenName = screenName;
        root.open = name;
    }

    function close() {
        root.open = "";
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

    // The output niri has focused, else the first screen's name.
    function focusedScreenName() {
        const name = Niri.focusedOutput();
        if (name !== "")
            return name;
        const list = Quickshell.screens;
        return list.length > 0 ? list[0].name : "";
    }
}
