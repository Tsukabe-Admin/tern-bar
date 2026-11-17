import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import "../singletons"
import "../singletons/looks.js" as LooksLib
import "views"

// Frame host: four invisible edge exclusion strips plus one fullscreen
// Top-layer surface rendering the connected screen frame, concave corners,
// flat top-lip bar slot, and one morphing popout drawer with curved wings.
Scope {
    id: root

    property var screenInfo: null
    property BarContent barContent: null
    readonly property var panelWindow: frameWin

    readonly property string screenName: root.screenInfo ? root.screenInfo.name : ""
    readonly property bool mediaReady: Popups.pickPlayer(Mpris.players.values || []) !== null
    readonly property string requestedKind: {
        if (!root.screenInfo || Popups.screenName !== root.screenName)
            return "";
        if (Popups.open === "media" && !root.mediaReady)
            return "";
        return Popups.open;
    }
    readonly property bool drawerOpen: root.requestedKind !== ""

    property string displayKind: ""
    property bool drawerVis: false
    property bool trackMorph: false

    function attachContent() {
        if (root.barContent)
            root.barContent.parent = barSlot;
    }

    onBarContentChanged: root.attachContent()
    Component.onCompleted: root.attachContent()
    Component.onDestruction: {
        if (root.barContent && root.barContent.parent === barSlot)
            root.barContent.parent = null;
    }

    onRequestedKindChanged: {
        if (root.requestedKind !== "") {
            const wasClosed = !root.drawerVis;
            closeTimer.stop();
            root.displayKind = root.requestedKind;
            root.drawerVis = true;
            if (wasClosed) {
                root.trackMorph = false;
                Qt.callLater(() => {
                    if (root.drawerOpen)
                        root.trackMorph = true;
                });
            } else {
                root.trackMorph = true;
            }
        } else if (root.drawerVis) {
            root.trackMorph = false;
            closeTimer.restart();
        }
    }

    Timer {
        id: closeTimer
        interval: Theme.motionBase
        onTriggered: {
            root.drawerVis = false;
            root.displayKind = "";
        }
    }

    Connections {
        target: Launcher
        function onOpenChanged() {
            if (Launcher.open && root.drawerVis) {
                closeTimer.stop();
                root.trackMorph = false;
                root.drawerVis = false;
                root.displayKind = "";
            }
        }
    }

    // ── Four click-through edge windows reserving compositor work area ──────
    PanelWindow {
        screen: root.screenInfo
        anchors.top: true
        implicitWidth: 1
        implicitHeight: Theme.barHeight
        exclusiveZone: Theme.barHeight
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "skua-frame-edge"
        focusable: false
        color: "transparent"
        mask: Region {}
    }

    PanelWindow {
        screen: root.screenInfo
        anchors.bottom: true
        implicitWidth: 1
        implicitHeight: Theme.frameThickness
        exclusiveZone: Theme.frameThickness
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "skua-frame-edge"
        focusable: false
        color: "transparent"
        mask: Region {}
    }

    PanelWindow {
        screen: root.screenInfo
        anchors.left: true
        implicitWidth: Theme.frameThickness
        implicitHeight: 1
        exclusiveZone: Theme.frameThickness
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "skua-frame-edge"
        focusable: false
        color: "transparent"
        mask: Region {}
    }

    PanelWindow {
        screen: root.screenInfo
        anchors.right: true
        implicitWidth: Theme.frameThickness
        implicitHeight: 1
        exclusiveZone: Theme.frameThickness
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "skua-frame-edge"
        focusable: false
        color: "transparent"
        mask: Region {}
    }

    // ── Main fullscreen frame surface ──────────────────────────────────────
    PanelWindow {
        id: frameWin

        screen: root.screenInfo
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "skua-frame"
        // Exclusive, like the launcher: a drawer opened from a keybind (or a
        // click on its pill) has to hear Esc without first being clicked.
        WlrLayershell.keyboardFocus: root.drawerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        // The whole screen takes input only while a drawer is open (a click
        // outside closes it). Idle, and while a drawer retracts, only the
        // frame itself does, so clicks reach the windows inside it.
        mask: root.drawerOpen ? null : idleMask

        Region {
            id: idleMask
            x: 0
            y: 0
            width: frameWin.width
            height: frameWin.height
            intersection: Intersection.Combine

            Region {
                x: Theme.frameThickness
                y: Theme.barHeight
                width: Math.max(0, frameWin.width - 2 * Theme.frameThickness)
                height: Math.max(0, frameWin.height - Theme.barHeight - Theme.frameThickness)
                radius: Theme.innerRounding
                intersection: Intersection.Xor
            }
        }

        FocusScope {
            id: frameScope
            anchors.fill: parent
            focus: root.drawerOpen
            Keys.onEscapePressed: Popups.close()

            readonly property int barH: Theme.barHeight
            readonly property int borderT: Theme.frameThickness
            readonly property int innerR: Theme.innerRounding
            readonly property real winW: frameWin.width
            readonly property real winH: frameWin.height
            readonly property color matColor: Theme.popBg
            readonly property color rimColor: Theme.rim

            readonly property real shadowExt: Theme.frameShadowEnabled ? Theme.frameShadowExtent : 0
            readonly property real sInnerLeft: frameScope.borderT
            readonly property real sInnerTop: frameScope.barH
            readonly property real sInnerRight: frameScope.winW - frameScope.borderT
            readonly property real sInnerBottom: frameScope.winH - frameScope.borderT
            readonly property real sInnerW: Math.max(0, frameScope.sInnerRight - frameScope.sInnerLeft)
            readonly property real sInnerH: Math.max(0, frameScope.sInnerBottom - frameScope.sInnerTop)
            readonly property real sCornerK: Math.max(frameScope.innerR, frameScope.shadowExt)
            readonly property real sKx: Math.min(frameScope.sCornerK, frameScope.sInnerW * 0.5)
            readonly property real sKy: Math.min(frameScope.sCornerK, frameScope.sInnerH * 0.5)
            readonly property real sTopStripH: Math.min(frameScope.shadowExt, frameScope.sKy)
            readonly property real sSideStripW: Math.min(frameScope.shadowExt, frameScope.sKx)
            readonly property real sBotStripH: Math.min(frameScope.shadowExt, frameScope.sKy)

            readonly property vector4d sInnerBoxVec: Qt.vector4d(
                frameScope.sInnerLeft, frameScope.sInnerTop,
                frameScope.sInnerRight, frameScope.sInnerBottom)
            readonly property vector4d sShadowVec: Qt.vector4d(
                Theme.frameShadowKeyOpacity, Theme.frameShadowAoOpacity,
                Theme.frameShadowSigma, Theme.frameShadowAoSigma)
            readonly property vector4d sGeomVec: Qt.vector4d(
                frameScope.innerR, Theme.frameShadowOffsetY,
                frameScope.shadowExt, 0.0)
            readonly property real activeTopWing: frameScope.launcherCutActive
                ? Launcher.activeCutWing
                : (frameScope.drawerCutActive ? frameScope.drawerCutWing : 0)
            readonly property vector4d sTopCutVec: Qt.vector4d(
                frameScope.topCutActive ? 1.0 : 0.0,
                frameScope.topCutLeft, frameScope.topCutRight,
                frameScope.activeTopWing)
            readonly property vector4d sTopAttachVec: frameScope.launcherCutActive
                ? Qt.vector4d(Launcher.activeCutX, Launcher.activeCutWidth, Launcher.activeCutHeight, Launcher.activeCutRadius)
                : (frameScope.drawerCutActive
                    ? Qt.vector4d(drawer.x, drawer.width, drawer.height, drawer.effR)
                    : Qt.vector4d(0, 0, 0, 0))
            readonly property vector4d sBotCutVec: Qt.vector4d(
                frameScope.bottomCutActive ? 1.0 : 0.0,
                frameScope.bottomCutLeft, frameScope.bottomCutRight, 0.0)

            // Outside-click backdrop dismissal while a drawer is open.
            MouseArea {
                anchors.fill: parent
                enabled: root.drawerOpen
                onClicked: Popups.close()
            }

            // ── Inward cutout bezel shadow (strictly inside viewport hole) ──
            Item {
                id: bezelShadowLayer
                anchors.fill: parent
                visible: Theme.frameShadowEnabled && frameScope.sInnerW > 0 && frameScope.sInnerH > 0

                // Four inner corner patches
                FrameShadowPatch {
                    x: frameScope.sInnerLeft
                    y: frameScope.sInnerTop
                    width: frameScope.sKx
                    height: frameScope.sKy
                    innerBox: frameScope.sInnerBoxVec
                    shadowParams: frameScope.sShadowVec
                    geomParams: frameScope.sGeomVec
                    topCut: frameScope.sTopCutVec
                    topAttach: frameScope.sTopAttachVec
                    botCut: frameScope.sBotCutVec
                }

                FrameShadowPatch {
                    x: frameScope.sInnerRight - frameScope.sKx
                    y: frameScope.sInnerTop
                    width: frameScope.sKx
                    height: frameScope.sKy
                    innerBox: frameScope.sInnerBoxVec
                    shadowParams: frameScope.sShadowVec
                    geomParams: frameScope.sGeomVec
                    topCut: frameScope.sTopCutVec
                    topAttach: frameScope.sTopAttachVec
                    botCut: frameScope.sBotCutVec
                }

                FrameShadowPatch {
                    x: frameScope.sInnerLeft
                    y: frameScope.sInnerBottom - frameScope.sKy
                    width: frameScope.sKx
                    height: frameScope.sKy
                    innerBox: frameScope.sInnerBoxVec
                    shadowParams: frameScope.sShadowVec
                    geomParams: frameScope.sGeomVec
                    topCut: frameScope.sTopCutVec
                    topAttach: frameScope.sTopAttachVec
                    botCut: frameScope.sBotCutVec
                }

                FrameShadowPatch {
                    x: frameScope.sInnerRight - frameScope.sKx
                    y: frameScope.sInnerBottom - frameScope.sKy
                    width: frameScope.sKx
                    height: frameScope.sKy
                    innerBox: frameScope.sInnerBoxVec
                    shadowParams: frameScope.sShadowVec
                    geomParams: frameScope.sGeomVec
                    topCut: frameScope.sTopCutVec
                    topAttach: frameScope.sTopAttachVec
                    botCut: frameScope.sBotCutVec
                }

                // Left & right straight edge strips
                FrameShadowPatch {
                    x: frameScope.sInnerLeft
                    y: frameScope.sInnerTop + frameScope.sKy
                    width: frameScope.sSideStripW
                    height: Math.max(0, frameScope.sInnerH - 2 * frameScope.sKy)
                    innerBox: frameScope.sInnerBoxVec
                    shadowParams: frameScope.sShadowVec
                    geomParams: frameScope.sGeomVec
                    topCut: frameScope.sTopCutVec
                    topAttach: frameScope.sTopAttachVec
                    botCut: frameScope.sBotCutVec
                }

                FrameShadowPatch {
                    x: frameScope.sInnerRight - frameScope.sSideStripW
                    y: frameScope.sInnerTop + frameScope.sKy
                    width: frameScope.sSideStripW
                    height: Math.max(0, frameScope.sInnerH - 2 * frameScope.sKy)
                    innerBox: frameScope.sInnerBoxVec
                    shadowParams: frameScope.sShadowVec
                    geomParams: frameScope.sGeomVec
                    topCut: frameScope.sTopCutVec
                    topAttach: frameScope.sTopAttachVec
                    botCut: frameScope.sBotCutVec
                }

                // Top straight strip (splits cleanly around open drawer or Launcher)
                FrameShadowPatch {
                    readonly property real startX: frameScope.sInnerLeft + frameScope.sKx
                    readonly property real endX: frameScope.sInnerRight - frameScope.sKx
                    readonly property real cutEnd: frameScope.topCutActive
                        ? Math.min(endX, frameScope.topCutLeft) : endX
                    x: startX
                    y: frameScope.sInnerTop
                    width: Math.max(0, cutEnd - startX)
                    height: frameScope.sTopStripH
                    innerBox: frameScope.sInnerBoxVec
                    shadowParams: frameScope.sShadowVec
                    geomParams: frameScope.sGeomVec
                    topCut: frameScope.sTopCutVec
                    topAttach: frameScope.sTopAttachVec
                    botCut: frameScope.sBotCutVec
                }

                FrameShadowPatch {
                    readonly property real startX: Math.max(
                        frameScope.sInnerLeft + frameScope.sKx, frameScope.topCutRight)
                    readonly property real endX: frameScope.sInnerRight - frameScope.sKx
                    visible: frameScope.topCutActive && endX > startX && frameScope.shadowExt > 0
                    x: startX
                    y: frameScope.sInnerTop
                    width: Math.max(0, endX - startX)
                    height: frameScope.sTopStripH
                    innerBox: frameScope.sInnerBoxVec
                    shadowParams: frameScope.sShadowVec
                    geomParams: frameScope.sGeomVec
                    topCut: frameScope.sTopCutVec
                    topAttach: frameScope.sTopAttachVec
                    botCut: frameScope.sBotCutVec
                }

                // Bottom straight strip (splits cleanly around bottom-docked OSD)
                FrameShadowPatch {
                    readonly property real startX: frameScope.sInnerLeft + frameScope.sKx
                    readonly property real endX: frameScope.sInnerRight - frameScope.sKx
                    readonly property real cutEnd: frameScope.bottomCutActive
                        ? Math.min(endX, frameScope.bottomCutLeft) : endX
                    x: startX
                    y: frameScope.sInnerBottom - frameScope.sBotStripH
                    width: Math.max(0, cutEnd - startX)
                    height: frameScope.sBotStripH
                    innerBox: frameScope.sInnerBoxVec
                    shadowParams: frameScope.sShadowVec
                    geomParams: frameScope.sGeomVec
                    topCut: frameScope.sTopCutVec
                    topAttach: frameScope.sTopAttachVec
                    botCut: frameScope.sBotCutVec
                }

                FrameShadowPatch {
                    readonly property real startX: Math.max(
                        frameScope.sInnerLeft + frameScope.sKx, frameScope.bottomCutRight)
                    readonly property real endX: frameScope.sInnerRight - frameScope.sKx
                    visible: frameScope.bottomCutActive && endX > startX && frameScope.shadowExt > 0
                    x: startX
                    y: frameScope.sInnerBottom - frameScope.sBotStripH
                    width: Math.max(0, endX - startX)
                    height: frameScope.sBotStripH
                    innerBox: frameScope.sInnerBoxVec
                    shadowParams: frameScope.sShadowVec
                    geomParams: frameScope.sGeomVec
                    topCut: frameScope.sTopCutVec
                    topAttach: frameScope.sTopAttachVec
                    botCut: frameScope.sBotCutVec
                }
            }

            // ── Non-overlapping frame border strips (safe at 92% alpha) ────
            Rectangle {
                x: 0
                y: 0
                width: frameScope.winW
                height: frameScope.barH
                color: frameScope.matColor
            }

            Rectangle {
                x: 0
                y: frameScope.barH
                width: frameScope.borderT
                height: Math.max(0, frameScope.winH - frameScope.barH - frameScope.borderT)
                color: frameScope.matColor
            }

            Rectangle {
                x: frameScope.winW - frameScope.borderT
                y: frameScope.barH
                width: frameScope.borderT
                height: Math.max(0, frameScope.winH - frameScope.barH - frameScope.borderT)
                color: frameScope.matColor
            }

            Rectangle {
                x: 0
                y: frameScope.winH - frameScope.borderT
                width: frameScope.winW
                height: frameScope.borderT
                color: frameScope.matColor
            }

            // ── Four concave inner cutout corners ──────────────────────────
            ConcaveCorner {
                corner: "topLeft"
                x: frameScope.borderT
                y: frameScope.barH
                radius: frameScope.innerR
                fillColor: frameScope.matColor
                strokeColor: frameScope.rimColor
            }

            ConcaveCorner {
                corner: "topRight"
                x: frameScope.winW - frameScope.borderT - frameScope.innerR
                y: frameScope.barH
                radius: frameScope.innerR
                fillColor: frameScope.matColor
                strokeColor: frameScope.rimColor
            }

            ConcaveCorner {
                corner: "bottomLeft"
                x: frameScope.borderT
                y: frameScope.winH - frameScope.borderT - frameScope.innerR
                radius: frameScope.innerR
                fillColor: frameScope.matColor
                strokeColor: frameScope.rimColor
            }

            ConcaveCorner {
                corner: "bottomRight"
                x: frameScope.winW - frameScope.borderT - frameScope.innerR
                y: frameScope.winH - frameScope.borderT - frameScope.innerR
                radius: frameScope.innerR
                fillColor: frameScope.matColor
                strokeColor: frameScope.rimColor
            }

            // ── Straight 1px inner hairlines (top splits around drawer) ────
            Rectangle {
                x: frameScope.borderT - 1
                y: frameScope.barH + frameScope.innerR
                width: 1
                height: Math.max(0, frameScope.winH - frameScope.barH - frameScope.borderT - 2 * frameScope.innerR)
                color: frameScope.rimColor
            }

            Rectangle {
                x: frameScope.winW - frameScope.borderT
                y: frameScope.barH + frameScope.innerR
                width: 1
                height: Math.max(0, frameScope.winH - frameScope.barH - frameScope.borderT - 2 * frameScope.innerR)
                color: frameScope.rimColor
            }

            readonly property real osdCutSpan: Popups.osdDockSpan(root.screenName)
            readonly property bool bottomCutActive: frameScope.osdCutSpan > 0
            readonly property real bottomCutLeft: (frameScope.winW - frameScope.osdCutSpan) * 0.5
            readonly property real bottomCutRight: (frameScope.winW + frameScope.osdCutSpan) * 0.5

            // Left segment of bottom hairline (full width when no bottom OSD is docked).
            Rectangle {
                readonly property real startX: frameScope.borderT + frameScope.innerR
                readonly property real endX: frameScope.winW - frameScope.borderT - frameScope.innerR
                readonly property real cutLeft: frameScope.bottomCutActive ? frameScope.bottomCutLeft : endX
                x: startX
                y: frameScope.winH - frameScope.borderT
                width: Math.max(0, Math.min(endX, cutLeft) - startX)
                height: 1
                color: frameScope.rimColor
            }

            // Right segment of bottom hairline when a docked OSD splits the bottom border.
            Rectangle {
                visible: frameScope.bottomCutActive
                readonly property real startX: frameScope.borderT + frameScope.innerR
                readonly property real endX: frameScope.winW - frameScope.borderT - frameScope.innerR
                readonly property real cutRight: Math.max(startX, frameScope.bottomCutRight)
                x: cutRight
                y: frameScope.winH - frameScope.borderT
                width: Math.max(0, endX - cutRight)
                height: 1
                color: frameScope.rimColor
            }

            // Not `Launcher.open`: the card still cuts the lip while it retracts.
            readonly property bool launcherCutActive: Theme.isFramed
                && Launcher.screenName === root.screenName
                && Launcher.activeCutRight > Launcher.activeCutLeft
            readonly property real drawerCutWing: drawer.wingR >= 2 ? drawer.wingR : 0
            readonly property bool drawerCutActive: root.drawerVis && drawer.height >= 2
            readonly property bool topCutActive: frameScope.drawerCutActive || frameScope.launcherCutActive
            readonly property real topCutLeft: frameScope.launcherCutActive
                ? Launcher.activeCutLeft : (drawer.x - frameScope.drawerCutWing)
            readonly property real topCutRight: frameScope.launcherCutActive
                ? Launcher.activeCutRight : (drawer.x + drawer.width + frameScope.drawerCutWing)

            // Left segment of top hairline (full width when no attached drawer/launcher is open).
            Rectangle {
                readonly property real startX: frameScope.borderT + frameScope.innerR
                readonly property real endX: frameScope.winW - frameScope.borderT - frameScope.innerR
                readonly property real cutLeft: frameScope.topCutActive ? frameScope.topCutLeft : endX
                x: startX
                y: frameScope.barH - 1
                width: Math.max(0, Math.min(endX, cutLeft) - startX)
                height: 1
                color: frameScope.rimColor
            }

            // Right segment of top hairline when a drawer splits the top border.
            Rectangle {
                visible: frameScope.topCutActive
                readonly property real startX: frameScope.borderT + frameScope.innerR
                readonly property real endX: frameScope.winW - frameScope.borderT - frameScope.innerR
                readonly property real cutRight: Math.max(startX, frameScope.topCutRight)
                x: cutRight
                y: frameScope.barH - 1
                width: Math.max(0, endX - cutRight)
                height: 1
                color: frameScope.rimColor
            }

            // ── Morphing popout drawer + concave wings ─────────────────────
            readonly property var currentViewItem: {
                switch (root.displayKind) {
                case "calendar": return calLoader.item;
                case "media": return mediaLoader.item;
                case "quick": return quickLoader.item;
                case "notifications": return notifyLoader.item;
                default: return null;
                }
            }

            readonly property Item anchorPill: root.barContent
                ? root.barContent.anchorForPopup(root.displayKind) : null

            readonly property real anchorCenterX: {
                if (!root.drawerVis || !frameScope.anchorPill || !frameScope.anchorPill.visible)
                    return frameScope.winW * 0.5;
                const p = frameScope.anchorPill.mapToItem(frameScope, frameScope.anchorPill.width * 0.5, 0);
                return p.x;
            }

            readonly property real targetW: frameScope.currentViewItem
                ? frameScope.currentViewItem.implicitWidth : 340
            readonly property real maxDrawerH: Math.max(160,
                frameScope.winH - frameScope.barH - frameScope.borderT - 20)
            readonly property real targetH: (root.drawerOpen && frameScope.currentViewItem)
                ? Math.min(frameScope.maxDrawerH, frameScope.currentViewItem.implicitHeight) : 0
            readonly property real drawerMinX: frameScope.borderT + frameScope.innerR + Theme.wingRadius
            readonly property real drawerMaxX: Math.max(drawerMinX + targetW,
                frameScope.winW - frameScope.borderT - frameScope.innerR - Theme.wingRadius)
            readonly property real targetX: LooksLib.clampDrawerX(
                frameScope.anchorCenterX, frameScope.targetW,
                frameScope.drawerMinX, frameScope.drawerMaxX)

            Connections {
                target: root
                function onDisplayKindChanged() {
                    if (root.trackMorph && root.displayKind !== "")
                        deckSwapAnim.restart();
                }
            }

            AttachedShadow {
                id: drawerShadow
                readonly property real pad: frameScope.shadowExt
                readonly property real wing: frameScope.drawerCutWing
                readonly property real leftX: Math.max(frameScope.sInnerLeft, drawer.x - wing - pad)
                readonly property real rightX: Math.min(frameScope.sInnerRight, drawer.x + drawer.width + wing + pad)
                readonly property real bottomY: Math.min(frameScope.sInnerBottom, frameScope.barH + drawer.height + pad)

                x: leftX
                y: frameScope.barH
                width: Math.max(0, rightX - leftX)
                height: Math.max(0, bottomY - frameScope.barH)
                z: 2
                visible: Theme.frameShadowEnabled && frameScope.drawerCutActive
                    && width > 0 && height > 0
                attachRect: Qt.vector4d(drawer.x, frameScope.barH, drawer.width, drawer.height)
                attachRadii: Qt.vector4d(drawer.effR, wing, 0.0, 0.0)
                innerBox: frameScope.sInnerBoxVec
                shadowParams: frameScope.sShadowVec
                geomParams: frameScope.sGeomVec
                cutSpan: frameScope.sTopCutVec
            }

            ConcaveCorner {
                corner: "topRight"
                visible: root.drawerVis && drawer.wingR >= 2
                x: drawer.x - drawer.wingR
                y: frameScope.barH
                radius: drawer.wingR
                fillColor: frameScope.matColor
                strokeColor: frameScope.rimColor
                z: 3
            }

            ConcaveCorner {
                corner: "topLeft"
                visible: root.drawerVis && drawer.wingR >= 2
                x: drawer.x + drawer.width
                y: frameScope.barH
                radius: drawer.wingR
                fillColor: frameScope.matColor
                strokeColor: frameScope.rimColor
                z: 3
            }

            // The drawer is part of the frame: its fill and wings stay solid
            // and it grows out of the lip and retracts into it. Only what is
            // inside fades (drawerScroll).
            Item {
                id: drawer

                visible: root.drawerVis
                x: frameScope.targetX
                y: frameScope.barH
                width: frameScope.targetW
                height: frameScope.targetH
                z: 4

                readonly property real effR: Math.max(1,
                    Math.min(Theme.radiusCard, drawer.height * 0.5, drawer.width * 0.5))
                readonly property real wingR: Math.min(Theme.wingRadius, Math.max(0, drawer.height - drawer.effR))

                Behavior on x {
                    enabled: !Looks.restyling && root.trackMorph
                    NumberAnimation {
                        duration: Theme.motionSlow
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveSpatial
                    }
                }

                Behavior on width {
                    enabled: !Looks.restyling && root.trackMorph
                    NumberAnimation {
                        duration: Theme.motionSlow
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveSpatial
                    }
                }

                // Morphing from one drawer to another, the height keeps time
                // with the width and the position.
                Behavior on height {
                    enabled: !Looks.restyling
                    NumberAnimation {
                        duration: root.trackMorph ? Theme.motionSlow : Theme.motionBase
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveEffects
                    }
                }

                // Drawer fill (top corners square where it fuses into bar lip).
                Rectangle {
                    anchors.fill: parent
                    topLeftRadius: 0
                    topRightRadius: 0
                    bottomLeftRadius: Theme.radiusCard
                    bottomRightRadius: Theme.radiusCard
                    color: frameScope.matColor
                    clip: true

                    // Absorb unhandled clicks on drawer padding/flanks so they don't hit the backdrop.
                    MouseArea {
                        anchors.fill: parent
                    }

                    // Taller than the screen allows (a small laptop panel):
                    // the whole view scrolls, with the wheel or a drag. A
                    // wheel area inside a view (the calendar's months) sits
                    // above this and still gets the wheel first.
                    Flickable {
                        id: drawerScroll
                        anchors.fill: parent
                        clip: true
                        interactive: contentHeight > height
                        contentWidth: width
                        contentHeight: frameScope.currentViewItem ? frameScope.currentViewItem.implicitHeight : 0
                        boundsBehavior: Flickable.StopAtBounds
                        opacity: root.drawerOpen ? 1 : 0

                        Behavior on opacity {
                            enabled: !Looks.restyling
                            NumberAnimation {
                                duration: Theme.motionFast
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.curveEffects
                            }
                        }

                        Item {
                            id: viewDeck
                            width: drawerScroll.width
                            height: Math.max(drawerScroll.height,
                                frameScope.currentViewItem ? frameScope.currentViewItem.implicitHeight : 0)

                            NumberAnimation {
                                id: deckSwapAnim
                                target: viewDeck
                                property: "opacity"
                                from: 0.35
                                to: 1.0
                                duration: Theme.motionFast
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.curveEffects
                            }

                            Loader {
                                id: calLoader
                                active: root.drawerVis && root.displayKind === "calendar"
                                anchors.horizontalCenter: parent.horizontalCenter
                                opacity: item ? 1 : 0
                                sourceComponent: Component {
                                    CalendarView {
                                        screenInfo: root.screenInfo
                                        active: root.drawerOpen && root.displayKind === "calendar"
                                    }
                                }
                            }

                            Loader {
                                id: mediaLoader
                                active: root.drawerVis && root.displayKind === "media"
                                anchors.horizontalCenter: parent.horizontalCenter
                                opacity: item ? 1 : 0
                                sourceComponent: Component {
                                    MediaView {
                                        screenInfo: root.screenInfo
                                        active: root.drawerOpen && root.displayKind === "media"
                                    }
                                }
                            }

                            Loader {
                                id: quickLoader
                                active: root.drawerVis && root.displayKind === "quick"
                                anchors.horizontalCenter: parent.horizontalCenter
                                opacity: item ? 1 : 0
                                sourceComponent: Component {
                                    QuickSettingsView {
                                        screenInfo: root.screenInfo
                                        active: root.drawerOpen && root.displayKind === "quick"
                                    }
                                }
                            }

                            Loader {
                                id: notifyLoader
                                active: root.drawerVis && root.displayKind === "notifications"
                                anchors.horizontalCenter: parent.horizontalCenter
                                opacity: item ? 1 : 0
                                sourceComponent: Component {
                                    NotificationsView {
                                        screenInfo: root.screenInfo
                                        active: root.drawerOpen && root.displayKind === "notifications"
                                    }
                                }
                            }
                        }
                    }
                }

                // 3-sided inner 1px hairline joining both ConcaveCorner wings.
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    antialiasing: true
                    visible: drawer.height >= 2 && drawer.width >= 4

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: frameScope.rimColor
                        strokeWidth: 1
                        capStyle: ShapePath.FlatCap

                        startX: 0.5
                        startY: drawer.wingR

                        PathLine {
                            x: 0.5
                            y: drawer.height - drawer.effR
                        }

                        PathArc {
                            x: drawer.effR
                            y: drawer.height - 0.5
                            radiusX: Math.max(0.5, drawer.effR - 0.5)
                            radiusY: Math.max(0.5, drawer.effR - 0.5)
                            useLargeArc: false
                            direction: PathArc.Counterclockwise
                        }

                        PathLine {
                            x: drawer.width - drawer.effR
                            y: drawer.height - 0.5
                        }

                        PathArc {
                            x: drawer.width - 0.5
                            y: drawer.height - drawer.effR
                            radiusX: Math.max(0.5, drawer.effR - 0.5)
                            radiusY: Math.max(0.5, drawer.effR - 0.5)
                            useLargeArc: false
                            direction: PathArc.Counterclockwise
                        }

                        PathLine {
                            x: drawer.width - 0.5
                            y: drawer.wingR
                        }
                    }
                }
            }

            // ── Top bar items slot (sits directly inside the top frame lip) ─
            Item {
                id: barSlot
                x: 0
                y: 0
                width: frameScope.winW
                height: frameScope.barH
                z: 5
            }
        }
    }
}
