import QtQuick
import Quickshell
import Quickshell.Wayland
import "../singletons"

// Brightness OSD: a capsule near the bottom of the focused screen for 1.5 s
// after the screen backlight changes. Click-through (empty input mask) and
// never takes the keyboard. Quiet for 2 s after start so starting the bar does
// not flash it.
PanelWindow {
    id: osd

    readonly property bool available: Brightness.available
    readonly property real val: Brightness.value
    property bool armed: false
    property bool shown: false
    property string screenName: ""

    screen: Popups.screenNamed(osd.screenName)
    visible: osd.shown && osd.available
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

    function poke() {
        if (!osd.armed || !osd.available)
            return;
        osd.screenName = Popups.focusedScreenName();
        osd.shown = true;
        hideTimer.restart();
    }

    onValChanged: osd.poke()
    onAvailableChanged: {
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
                text: osd.val < 0.34 ? "󰃞" : osd.val < 0.67 ? "󰃟" : "󰃠"
                color: Theme.t1
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
                    width: parent.width * Math.max(0, Math.min(1, osd.val))
                    height: parent.height
                    radius: 3
                    color: Theme.accent

                    Behavior on width {
                        NumberAnimation { duration: Theme.motionFast; easing.type: Easing.OutCubic }
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                text: Math.round(osd.val * 100) + "%"
                color: Theme.t1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }
    }
}
