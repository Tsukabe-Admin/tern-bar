import QtQuick
import Quickshell
import Quickshell.Wayland
import "../singletons"

// The bar's own short messages (Notice.show): a capsule near the bottom of the
// focused screen for two seconds, in the place and style of the volume and
// brightness OSDs. Click-through (empty input mask) and never takes the keyboard.
PanelWindow {
    id: osd

    property bool shown: false
    property string screenName: ""
    readonly property bool onFullscreen: osd.screenName !== "" && Compositor.isOutputFullscreen(osd.screenName)
    readonly property bool docked: Theme.isFramed && !osd.onFullscreen

    function syncDock() {
        Popups.reportOsdDock("notice", osd.screenName, osd.visible && osd.docked, surface.activeCutSpan);
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
    Component.onDestruction: Popups.reportOsdDock("notice", "", false, 0)

    Connections {
        target: Notice

        function onSerialChanged() {
            osd.screenName = Popups.focusedScreenName();
            osd.shown = true;
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: osd.shown = false
    }

    OsdSurface {
        id: surface
        active: osd.shown
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
                text: Notice.icon
                color: Theme.t1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 2
            }

            // What is left of the tab after its padding, the icon and the gap.
            Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, surface.tabWidth - 32 - 20 - 12)
                elide: Text.ElideRight
                text: Notice.text
                color: Theme.t1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }
    }
}
