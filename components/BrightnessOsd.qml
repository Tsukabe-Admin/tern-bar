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
    readonly property bool onFullscreen: osd.screenName !== "" && Compositor.isOutputFullscreen(osd.screenName)
    readonly property bool docked: Theme.isFramed && !osd.onFullscreen

    function syncDock() {
        Popups.reportOsdDock("brightness", osd.screenName, osd.visible && osd.docked, surface.activeCutSpan);
    }

    // Mapped for as long as the surface has something to show: while `shown`,
    // and in the Frame look while the docked tab retracts afterwards.
    screen: Popups.screenNamed(osd.screenName)
    visible: surface.presented
    anchors.bottom: true
    margins.bottom: osd.docked
        ? Math.max(0, Theme.frameThickness - 1)
        : (Theme.isFramed ? Math.max(0, 36 - surface.shadowPadBottom) : 96)
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: surface.implicitWidth
    implicitHeight: surface.implicitHeight
    color: "transparent"
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "skua-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    onVisibleChanged: osd.syncDock()
    onDockedChanged: osd.syncDock()
    onScreenNameChanged: osd.syncDock()
    Component.onDestruction: Popups.reportOsdDock("brightness", "", false, 0)

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

    OsdSurface {
        id: surface
        active: osd.shown && osd.available
        docked: osd.docked
        tabWidth: 260
        tabHeight: 44
        onActiveCutSpanChanged: osd.syncDock()

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
