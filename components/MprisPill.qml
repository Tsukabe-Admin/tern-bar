import QtQuick
import Quickshell.Services.Mpris
import "../singletons"

// Media pill: prefers the selected or playing player, falls back to the first
// one. Hidden when nothing is on the bus. Left-click opens the media popup;
// right-click or middle-click toggles playback directly.
BarItem {
    id: root

    readonly property var player: Popups.pickPlayer(Mpris.players.values)
    readonly property bool hasPlayer: root.player !== null

    function togglePlay() {
        if (!root.player)
            return;
        if (root.player.canTogglePlaying)
            root.player.togglePlaying();
        else if (root.player.isPlaying && root.player.canPause)
            root.player.pause();
        else if (!root.player.isPlaying && root.player.canPlay)
            root.player.play();
    }

    text: {
        var p = root.player;
        if (!p)
            return "";
        var icon = (p.identity && p.identity.toLowerCase().indexOf("spotify") !== -1) ? "󰓇" : "󰎆";
        var title = p.trackTitle || p.identity || "";
        return icon + "  " + (title.length > 35 ? title.substr(0, 35) : title);
    }
    fg: Theme.t2

    onRightClicked: root.togglePlay()
    onMiddleClicked: root.togglePlay()
}
