import QtQuick
import Quickshell
import Quickshell.Wayland
import "singletons"

// The Tern launch morph: a capsule of the terminal's own black grows out of the
// Tern pill toward the tile the terminal will occupy, holds while the client
// starts (so nothing pops in half-drawn), then dissolves into the real window.
// It sits on the overlay layer, and its clickthrough mask is exactly the shape,
// so nothing else on screen is blocked.
PanelWindow {
    id: overlay

    required property var screenInfo
    required property string screenName

    screen: screenInfo
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    color: "transparent"
    visible: false
    focusable: false
    mask: Region { item: shape }

    property bool running: false
    property bool fading: false
    property rect fromRect: Qt.rect(0, 0, 0, 0)
    property rect toRect: Qt.rect(0, 0, 0, 0)
    property var knownTernIds: []
    property double startedAt: 0

    function ternIdsNow() {
        var out = [];
        var list = Niri.windows;
        for (var i = 0; i < list.length; i++) {
            if (list[i].app_id === "so.stencil.tern")
                out.push(list[i].id);
        }
        return out;
    }

    function newTernWindow() {
        var list = Niri.windows;
        for (var i = 0; i < list.length; i++) {
            var w = list[i];
            if (w.app_id === "so.stencil.tern" && overlay.knownTernIds.indexOf(w.id) === -1)
                return true;
        }
        return false;
    }

    // `item` is the pill (in the bar window) the morph starts from.
    function launchFrom(item) {
        if (overlay.running)
            return;
        const p = item.mapToItem(null, 0, 0);
        overlay.fromRect = Qt.rect(Theme.barMarginSide + p.x, Theme.barMarginTop + p.y, item.width, item.height);
        // The overlay window is not realized yet, so aim with the screen size
        // (the work area, inset by niri's gaps below the reserved bar strip).
        // config.kdl's default-column-width is 0.5, so the new terminal lands
        // centered at half the work area — aim there for a seamless dissolve.
        const tileW = (overlay.screenInfo.width - 2 * Theme.workAreaGap) * 0.5;
        overlay.toRect = Qt.rect((overlay.screenInfo.width - tileW) / 2,
                                 Theme.workAreaTop + Theme.workAreaGap,
                                 tileW,
                                 overlay.screenInfo.height - Theme.workAreaTop - 2 * Theme.workAreaGap);
        overlay.knownTernIds = overlay.ternIdsNow();
        overlay.startedAt = Date.now();
        overlay.fading = false;
        overlay.running = true;
        overlay.visible = true;
        Niri.focusMonitor(overlay.screenName);
        launchTimer.restart();
        watchTimer.restart();
    }

    // Dissolve as soon as the terminal window exists (or after a second if it
    // does not — e.g. an existing window is focused instead, or a slow client).
    function maybeFinish() {
        if (!overlay.running || overlay.fading)
            return;
        const elapsed = Date.now() - overlay.startedAt;
        if (elapsed < Theme.motionSlow + 60)
            return; // let the shape arrive before revealing anything
        if (overlay.newTernWindow() || elapsed > 700) {
            overlay.fading = true;
            doneTimer.restart();
        }
    }

    Rectangle {
        id: shape
        x: overlay.running ? overlay.toRect.x : overlay.fromRect.x
        y: overlay.running ? overlay.toRect.y : overlay.fromRect.y
        width: overlay.running ? overlay.toRect.width : overlay.fromRect.width
        height: overlay.running ? overlay.toRect.height : overlay.fromRect.height
        radius: overlay.running ? Theme.radiusCard : Theme.pillRadius
        color: Theme.morphFill
        border.width: 1
        border.color: Theme.rim
        opacity: overlay.fading ? 0 : 1

        // OutSine, not OutCubic: OutCubic covers ~80% of the travel in the first
        // third, which read as a black flash instead of a growth.
        Behavior on x {
            NumberAnimation {
                duration: Theme.motionSlow
                easing.type: Easing.OutSine
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: Theme.motionSlow
                easing.type: Easing.OutSine
            }
        }
        Behavior on width {
            NumberAnimation {
                duration: Theme.motionSlow
                easing.type: Easing.OutSine
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: Theme.motionSlow
                easing.type: Easing.OutSine
            }
        }
        Behavior on radius {
            NumberAnimation {
                duration: Theme.motionSlow
                easing.type: Easing.OutSine
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.motionBase
                easing.type: Easing.OutCubic
            }
        }
    }

    Timer {
        id: launchTimer
        interval: 80
        onTriggered: Tern.open()
    }

    Timer {
        id: watchTimer
        interval: 60
        repeat: true
        running: overlay.running && !overlay.fading
        onTriggered: overlay.maybeFinish()
    }

    Timer {
        id: doneTimer
        interval: Theme.motionBase + 140
        onTriggered: {
            overlay.running = false;
            overlay.fading = false;
            overlay.visible = false;
        }
    }
}
