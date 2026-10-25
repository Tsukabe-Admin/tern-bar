import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import "../singletons"

// Expanded MPRIS media player card under the media pill. Shows a player
// selector when multiple players are on the bus, album artwork, title/artist/
// album metadata, an interactive progress/seek bar, and transport controls.
PopupWindow {
    id: pop

    property var barWindow: null
    property var screenInfo: null
    property Item anchorItem: null

    readonly property var players: Mpris.players.values || []
    readonly property var player: Popups.pickPlayer(pop.players)

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
        return (pop.allowRemoteArt && /^https?:/.test(s)) ? s : "";
    }

    visible: Popups.open === "media" && pop.screenInfo !== null
        && Popups.screenName === pop.screenInfo.name && pop.player !== null
    anchor.window: pop.barWindow
    anchor.rect.x: 0
    anchor.rect.y: 0
    anchor.rect.width: 1
    anchor.rect.height: 1
    grabFocus: false
    color: "transparent"
    implicitWidth: (pop.screenInfo ? pop.screenInfo.width : 1000) - Theme.barMarginSide
    implicitHeight: (pop.screenInfo ? pop.screenInfo.height : 1000) - Theme.barMarginTop

    readonly property bool hasAnchor: pop.anchorItem !== null && pop.anchorItem.visible
    readonly property point anchorPos: (pop.visible && pop.hasAnchor)
        ? pop.anchorItem.mapToItem(null, 0, 0) : Qt.point(0, 0)

    readonly property real trackLen: (pop.player && pop.player.length > 0) ? pop.player.length : 0
    readonly property real trackPos: (pop.player && pop.player.position >= 0) ? pop.player.position : 0

    function formatTime(secs) {
        const s = Math.max(0, Math.floor(Number(secs) || 0));
        const m = Math.floor(s / 60);
        const rem = s % 60;
        return m + ":" + (rem < 10 ? "0" : "") + rem;
    }

    onPlayerChanged: {
        if (!pop.player && Popups.open === "media")
            Popups.close();
    }

    // Quickshell's MprisPlayer.position only emits positionChanged on D-Bus
    // seeks unless polled while visible.
    Timer {
        interval: 1000
        repeat: true
        running: pop.visible && pop.player !== null && pop.player.isPlaying && pop.player.positionSupported
        onTriggered: {
            if (pop.player && pop.player.positionSupported)
                pop.player.positionChanged();
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: pop.visible
        onClicked: Popups.close()
    }

    Rectangle {
        id: card
        width: 320
        height: col.implicitHeight + 24
        x: pop.hasAnchor
            ? Math.max(0, Math.min(pop.anchorPos.x + pop.anchorItem.width / 2 - card.width / 2, pop.width - card.width))
            : Math.max(0, Math.round((pop.width - card.width) / 2))
        y: Theme.barHeight + 4
        radius: Theme.radiusCard
        color: Theme.popBg
        border.width: 1
        border.color: Theme.rim

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: col
            x: 12
            y: 12
            width: card.width - 24
            spacing: 12

            // Player selector when more than one MPRIS player is active.
            Flow {
                visible: pop.players.length > 1
                width: parent.width
                spacing: 6

                Repeater {
                    model: pop.players

                    Chip {
                        required property var modelData
                        text: modelData.identity || "Player"
                        selected: modelData === pop.player
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
                        text: (pop.player && pop.player.identity
                            && pop.player.identity.toLowerCase().indexOf("spotify") !== -1) ? "󰓇" : "󰎆"
                        color: Theme.t2
                        font.family: Theme.fontFamily
                        font.pixelSize: 26
                    }

                    Image {
                        id: artImg
                        anchors.fill: parent
                        source: pop.player ? pop.artSource(pop.player.trackArtUrl) : ""
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
                        text: (pop.player && pop.player.trackTitle) ? pop.player.trackTitle : "Unknown title"
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
                            if (!pop.player)
                                return "";
                            return pop.player.trackArtist || pop.player.trackAlbumArtist || pop.player.identity || "";
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
                        text: (pop.player && pop.player.trackAlbum) ? pop.player.trackAlbum : ""
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: Theme.t3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
            }

            Column {
                visible: pop.trackLen > 0
                width: parent.width
                spacing: 2

                SettingsSlider {
                    id: seekSlider
                    width: parent.width
                    from: 0
                    to: Math.max(1, pop.trackLen)
                    stepSize: 1
                    value: Math.min(pop.trackLen, pop.trackPos)
                    enabled: !!(pop.player && pop.player.canSeek)
                    onCommitted: (val) => {
                        if (!pop.player || !pop.player.canSeek)
                            return;
                        if (pop.player.positionSupported)
                            pop.player.position = val;
                        else
                            pop.player.seek(val - pop.trackPos);
                    }
                }

                Item {
                    width: parent.width
                    height: 16

                    Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: pop.formatTime(seekSlider.shownValue)
                        color: Theme.t3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: pop.formatTime(pop.trackLen)
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
                    opacity: (pop.player && pop.player.canGoPrevious) ? 1 : 0.35

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
                        enabled: !!(pop.player && pop.player.canGoPrevious)
                        onTapped: pop.player.previous()
                    }
                }

                Rectangle {
                    id: playBtn
                    readonly property bool hovered: playHover.hovered
                    width: 42
                    height: 42
                    radius: 21
                    color: Theme.accent
                    opacity: (pop.player && (pop.player.canTogglePlaying || pop.player.canPlay || pop.player.canPause))
                        ? (playBtn.hovered ? 0.88 : 1) : 0.4

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: (pop.player && pop.player.isPlaying) ? "󰏤" : "󰐊"
                        color: Theme.card
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 6
                    }

                    HoverHandler { id: playHover }
                    TapHandler {
                        enabled: !!(pop.player && (pop.player.canTogglePlaying || pop.player.canPlay || pop.player.canPause))
                        onTapped: {
                            if (!pop.player)
                                return;
                            if (pop.player.canTogglePlaying)
                                pop.player.togglePlaying();
                            else if (pop.player.isPlaying && pop.player.canPause)
                                pop.player.pause();
                            else if (!pop.player.isPlaying && pop.player.canPlay)
                                pop.player.play();
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
                    opacity: (pop.player && pop.player.canGoNext) ? 1 : 0.35

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
                        enabled: !!(pop.player && pop.player.canGoNext)
                        onTapped: pop.player.next()
                    }
                }
            }
        }
    }
}
