import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import "../../singletons"
import ".."

// Expanded MPRIS media player body, shared between the classic popup and the
// Frame morphing drawer. Shows a player selector when multiple players are on
// the bus, album artwork, title/artist/album metadata, an interactive
// progress/seek bar, and transport controls.
Item {
    id: view

    property var screenInfo: null
    property bool active: false

    readonly property var players: Mpris.players.values || []
    readonly property var player: Popups.pickPlayer(view.players)

    // Album art is remote content controlled by the MPRIS player. Loading an
    // https URL here is a tracking pixel, so local schemes only by default;
    // set TERN_BAR_REMOTE_ART=1 to opt back into remote art.
    readonly property bool allowRemoteArt: Quickshell.env("TERN_BAR_REMOTE_ART") === "1"

    function artSource(url) {
        const s = url ? String(url) : "";
        if (s === "")
            return "";
        if (/^(file|image):/.test(s) || /^data:image\//.test(s))
            return s;
        return (view.allowRemoteArt && /^https?:/.test(s)) ? s : "";
    }

    readonly property real trackLen: (view.player && view.player.length > 0) ? view.player.length : 0
    readonly property real trackPos: (view.player && view.player.position >= 0) ? view.player.position : 0

    function formatTime(secs) {
        const s = Math.max(0, Math.floor(Number(secs) || 0));
        const m = Math.floor(s / 60);
        const rem = s % 60;
        return m + ":" + (rem < 10 ? "0" : "") + rem;
    }

    onPlayerChanged: {
        if (!view.player && Popups.open === "media")
            Popups.close();
    }

    implicitWidth: 320
    implicitHeight: col.implicitHeight + 24
    width: view.implicitWidth
    height: view.implicitHeight

    // Quickshell's MprisPlayer.position only emits positionChanged on D-Bus
    // seeks unless polled while visible.
    Timer {
        interval: 1000
        repeat: true
        running: view.active && view.player !== null && view.player.isPlaying && view.player.positionSupported
        onTriggered: {
            if (view.player && view.player.positionSupported)
                view.player.positionChanged();
        }
    }

    MouseArea {
        anchors.fill: parent
    }

    Column {
        id: col
        x: 12
        y: 12
        width: view.implicitWidth - 24
        spacing: 12

        // Player selector when more than one MPRIS player is active.
        Flow {
            visible: view.players.length > 1
            width: parent.width
            spacing: 6

            Repeater {
                model: view.players

                Chip {
                    required property var modelData
                    text: modelData.identity || "Player"
                    selected: modelData === view.player
                    onClicked: Popups.preferredPlayer = modelData.dbusName
                }
            }
        }

        Row {
            width: parent.width
            spacing: 12

            ClippingRectangle {
                id: artBox
                width: 64
                height: 64
                radius: Theme.itemRadius
                color: Theme.l3

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: artImg.status !== Image.Ready
                    text: (view.player && view.player.identity
                        && view.player.identity.toLowerCase().indexOf("spotify") !== -1) ? "󰓇" : "󰎆"
                    color: Theme.t2
                    font.family: Theme.fontFamily
                    font.pixelSize: 26
                }

                Image {
                    id: artImg
                    anchors.fill: parent
                    source: view.player ? view.artSource(view.player.trackArtUrl) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
            }

            Column {
                width: parent.width - artBox.width - 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: (view.player && view.player.trackTitle) ? view.player.trackTitle : "Unknown title"
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: Theme.t1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    visible: text !== ""
                    text: {
                        if (!view.player)
                            return "";
                        return view.player.trackArtist || view.player.trackAlbumArtist || view.player.identity || "";
                    }
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: Theme.t2
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    visible: text !== ""
                    text: (view.player && view.player.trackAlbum) ? view.player.trackAlbum : ""
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }

        Column {
            visible: view.trackLen > 0
            width: parent.width
            spacing: 2

            SettingsSlider {
                id: seekSlider
                width: parent.width
                from: 0
                to: Math.max(1, view.trackLen)
                stepSize: 1
                value: Math.min(view.trackLen, view.trackPos)
                enabled: !!(view.player && view.player.canSeek)
                onCommitted: (val) => {
                    if (!view.player || !view.player.canSeek)
                        return;
                    if (view.player.positionSupported)
                        view.player.position = val;
                    else
                        view.player.seek(val - view.trackPos);
                }
            }

            Item {
                width: parent.width
                height: 16

                Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: view.formatTime(seekSlider.shownValue)
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: view.formatTime(view.trackLen)
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16

            Rectangle {
                id: prevBtn
                readonly property bool hovered: prevHover.hovered
                width: 36
                height: 36
                radius: 18
                color: prevBtn.hovered ? Theme.hover : "transparent"
                opacity: (view.player && view.player.canGoPrevious) ? 1 : 0.35

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "󰒮"
                    color: Theme.t1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 4
                }

                HoverHandler { id: prevHover }
                TapHandler {
                    enabled: !!(view.player && view.player.canGoPrevious)
                    onTapped: view.player.previous()
                }
            }

            Rectangle {
                id: playBtn
                readonly property bool hovered: playHover.hovered
                width: 42
                height: 42
                radius: 21
                color: Theme.accent
                opacity: (view.player && (view.player.canTogglePlaying || view.player.canPlay || view.player.canPause))
                    ? (playBtn.hovered ? 0.88 : 1) : 0.4

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: (view.player && view.player.isPlaying) ? "󰏤" : "󰐊"
                    color: Theme.accentInk
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 6
                }

                HoverHandler { id: playHover }
                TapHandler {
                    enabled: !!(view.player && (view.player.canTogglePlaying || view.player.canPlay || view.player.canPause))
                    onTapped: {
                        if (!view.player)
                            return;
                        if (view.player.canTogglePlaying)
                            view.player.togglePlaying();
                        else if (view.player.isPlaying && view.player.canPause)
                            view.player.pause();
                        else if (!view.player.isPlaying && view.player.canPlay)
                            view.player.play();
                    }
                }
            }

            Rectangle {
                id: nextBtn
                readonly property bool hovered: nextHover.hovered
                width: 36
                height: 36
                radius: 18
                color: nextBtn.hovered ? Theme.hover : "transparent"
                opacity: (view.player && view.player.canGoNext) ? 1 : 0.35

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "󰒭"
                    color: Theme.t1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 4
                }

                HoverHandler { id: nextHover }
                TapHandler {
                    enabled: !!(view.player && view.player.canGoNext)
                    onTapped: view.player.next()
                }
            }
        }
    }
}
