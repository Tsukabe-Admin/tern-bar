import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import "../singletons"

// Volume OSD: a capsule near the bottom of the focused screen for 1.5 s after
// the default output's volume or mute changes. Click-through (empty input
// mask) and never takes the keyboard. Quiet for 2 s after start and after the
// default output switches, so starting the bar or plugging headphones in does
// not flash it.
PanelWindow {
    id: osd

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: (osd.sink && osd.sink.audio) ? osd.sink.audio.volume : 0
    readonly property bool muted: (osd.sink && osd.sink.audio) ? osd.sink.audio.muted : false
    property bool armed: false
    property bool shown: false
    property string screenName: ""

    screen: Popups.screenNamed(osd.screenName)
    visible: osd.shown
    anchors.bottom: true
    margins.bottom: 96
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 260
    implicitHeight: 44
    color: "transparent"
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "tern-bar-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None


    PwObjectTracker {
        objects: osd.sink ? [osd.sink] : []
    }

    function poke() {
        if (!osd.armed)
            return;
        osd.screenName = Popups.focusedScreenName();
        osd.shown = true;
        hideTimer.restart();
    }

    onVolChanged: osd.poke()
    onMutedChanged: osd.poke()
    onSinkChanged: {
        osd.armed = false;
        armTimer.restart();
    }

    Timer {
        id: armTimer
        interval: 2000
        running: true
        onTriggered: osd.armed = true
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: osd.shown = false
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.popBg
        border.width: 1
        border.color: Theme.rim

        Row {
            anchors.centerIn: parent
            spacing: 12

            Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                horizontalAlignment: Text.AlignHCenter
                text: osd.muted ? "󰝟" : osd.vol < 0.34 ? "󰕿" : osd.vol < 0.67 ? "󰖀" : "󰕾"
                color: osd.muted ? Theme.t3 : Theme.t1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 2
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 150
                height: 6
                radius: 3
                color: Theme.l3

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, osd.vol))
                    height: parent.height
                    radius: 3
                    color: osd.muted ? Theme.t3 : Theme.accent

                    Behavior on width {
                        NumberAnimation { duration: Theme.motionFast; easing.type: Easing.OutCubic }
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                text: osd.muted ? "Muted" : Math.round(osd.vol * 100) + "%"
                color: Theme.t1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }
    }
}
