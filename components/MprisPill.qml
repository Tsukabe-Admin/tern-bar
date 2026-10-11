import QtQuick
import Quickshell.Services.Mpris
import "../singletons"

// Media pill: prefers the playing player, falls back to the first one.
// Hidden when nothing is on the bus. Click toggles playback.
BarItem {
    id: root

    readonly property var player: pickPlayer()
    readonly property bool hasPlayer: root.player !== null

    function pickPlayer() {
        var arr = Mpris.players.values;
        if (!arr)
            return null;
        var first = null;
        for (var i = 0; i < arr.length; i++) {
            var p = arr[i];
            if (!first)
                first = p;
            if (p.isPlaying)
                return p;
        }
        return first;
    }

    visible: root.hasPlayer
    text: {
        var p = root.player;
        if (!p)
            return "";
        var icon = (p.identity && p.identity.toLowerCase().indexOf("spotify") !== -1) ? "󰓇" : "󰎆";
        var title = p.trackTitle || "";
        return icon + "  " + (title.length > 35 ? title.substr(0, 35) : title);
    }
    fg: Theme.t2

    onClicked: {
        if (root.player && root.player.canTogglePlaying)
            root.player.togglePlaying();
    }
}
