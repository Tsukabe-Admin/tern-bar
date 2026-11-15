import QtQuick
import QtQuick.Shapes
import "../singletons"

// Shared OSD surface container. Classic Tern: a floating capsule that appears
// and goes at once, as it always has. Tern Frame: a tab docked into the
// bottom lip with curved ConcaveCorner wings, which grows out of the lip and
// retracts into it; over a fullscreen window (the frame is hidden under it)
// a floating capsule that fades in.
Item {
    id: root

    // The owner wants the OSD on screen.
    property bool active: false
    // The owner's window has to be mapped: active, or still retracting.
    property bool presented: false
    property bool docked: Theme.isFramed
    property int tabWidth: 260
    property int tabHeight: 44
    readonly property int wingRadius: root.docked ? Theme.wingRadius : 0
    property real openReveal: 1.0
    property real openOffset: 0

    readonly property real bodyH: root.docked
        ? Math.max(0, Math.round(root.tabHeight * root.openReveal))
        : root.tabHeight
    readonly property real effR: Math.max(1,
        Math.min(Theme.radiusCard, root.bodyH * 0.5, root.tabWidth * 0.5))
    readonly property real wingR: root.docked
        ? Math.min(root.wingRadius, Math.max(0, root.bodyH - root.effR))
        : 0
    readonly property real activeCutSpan: (root.presented && root.docked && root.bodyH >= 2)
        ? (root.tabWidth + (root.wingR >= 2 ? 2 * root.wingR : 0))
        : 0

    readonly property int shadowExt: (Theme.isFramed && Theme.frameShadowEnabled) ? Theme.frameShadowExtent : 0
    readonly property int shadowPadSide: root.shadowExt
    readonly property int shadowPadTop: root.shadowExt
    readonly property int shadowPadBottom: root.docked ? 0 : (root.shadowExt > 0 ? root.shadowExt + 8 : 0)

    default property alias content: inner.data

    // In docked Frame mode reserve 1 extra bottom pixel row matching FrameHost's
    // bottom hairline (winH - borderT) so ConcaveCorner stroke tips join without clipping.
    implicitWidth: root.tabWidth + 2 * root.wingRadius + 2 * root.shadowPadSide
    implicitHeight: (root.docked ? (root.tabHeight + 1) : root.tabHeight) + root.shadowPadTop + root.shadowPadBottom
    width: implicitWidth
    height: implicitHeight

    onActiveChanged: {
        dockRevealAnim.stop();
        dockRetractAnim.stop();
        floatRevealAnim.stop();
        if (root.active) {
            const fresh = !root.presented;
            root.presented = true;
            if (root.docked) {
                // Shown again while it was retracting: carry on from where it is.
                if (fresh) {
                    root.openReveal = 0;
                    inner.opacity = 0;
                }
                root.openOffset = 0;
                visualBody.opacity = 1;
                dockRevealAnim.restart();
            } else if (Theme.isFramed) {
                root.openReveal = 1.0;
                root.openOffset = 8;
                inner.opacity = 1;
                visualBody.opacity = 0;
                floatRevealAnim.restart();
            } else {
                root.openReveal = 1.0;
                root.openOffset = 0;
                inner.opacity = 1;
                visualBody.opacity = 1;
            }
        } else if (root.presented && root.docked && !Looks.restyling) {
            dockRetractAnim.restart();
        } else {
            root.presented = false;
        }
    }

    // Docked: the tab is part of the frame, so it stays solid and only what
    // is in it fades.
    ParallelAnimation {
        id: dockRevealAnim
        NumberAnimation {
            target: inner
            property: "opacity"
            to: 1
            duration: Theme.motionFast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveEffects
        }
        NumberAnimation {
            target: root
            property: "openReveal"
            to: 1
            duration: Theme.motionBase
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveEffects
        }
    }

    ParallelAnimation {
        id: dockRetractAnim
        NumberAnimation {
            target: inner
            property: "opacity"
            to: 0
            duration: Theme.motionFast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveEffects
        }
        NumberAnimation {
            target: root
            property: "openReveal"
            to: 0
            duration: Theme.motionBase
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveEffects
        }
        onFinished: if (!root.active) root.presented = false
    }

    ParallelAnimation {
        id: floatRevealAnim
        NumberAnimation {
            target: visualBody
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.motionFast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveEffects
        }
        NumberAnimation {
            target: root
            property: "openOffset"
            from: 8
            to: 0
            duration: Theme.motionBase
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveEffects
        }
    }

    AttachedShadow {
        id: osdShadow
        readonly property real bodyX: root.shadowPadSide + root.wingRadius
        readonly property real bodyTopY: root.shadowPadTop + (root.docked ? (root.tabHeight - root.bodyH) : root.openOffset)
        readonly property real wing: (root.docked && root.wingR >= 2) ? root.wingR : 0

        x: 0
        y: 0
        width: root.width
        height: root.height
        visible: Theme.isFramed && Theme.frameShadowEnabled && root.presented
            && (root.docked ? root.bodyH >= 2 : true)
            && width > 0 && height > 0
        attachRect: Qt.vector4d(bodyX, bodyTopY, root.tabWidth, root.bodyH)
        attachRadii: Qt.vector4d(
            root.docked ? root.effR : (root.bodyH * 0.5),
            wing,
            root.docked ? 1.0 : 2.0,
            0.0)
        innerBox: Qt.vector4d(0, 0, root.width, root.shadowPadTop + root.tabHeight)
        shadowParams: Qt.vector4d(
            Theme.frameShadowKeyOpacity, Theme.frameShadowAoOpacity,
            Theme.frameShadowSigma, Theme.frameShadowAoSigma)
        geomParams: Qt.vector4d(
            Theme.innerRounding, Theme.frameShadowOffsetY,
            root.shadowExt, 0.0)
        cutSpan: Qt.vector4d(
            (root.docked && root.bodyH >= 2) ? 1.0 : 0.0,
            bodyX - wing,
            bodyX + root.tabWidth + wing,
            0.0)
        attachOpacity: visualBody.opacity
    }

    Item {
        id: visualBody
        x: root.shadowPadSide
        y: root.shadowPadTop + (root.docked ? 0 : root.openOffset)
        width: root.tabWidth + 2 * root.wingRadius
        height: root.docked ? (root.tabHeight + 1) : root.tabHeight

        // Left & right concave wings anchored onto the bottom frame hairline.
        ConcaveCorner {
            corner: "bottomRight"
            visible: root.docked && root.wingR >= 2
            x: root.wingRadius - root.wingR
            y: root.tabHeight - root.wingR
            radius: root.wingR
            fillColor: Theme.popBg
            strokeColor: Theme.rim
        }

        ConcaveCorner {
            corner: "bottomLeft"
            visible: root.docked && root.wingR >= 2
            x: root.wingRadius + root.tabWidth
            y: root.tabHeight - root.wingR
            radius: root.wingR
            fillColor: Theme.popBg
            strokeColor: Theme.rim
        }

        // Main capsule / docked tab background.
        Rectangle {
            id: body
            x: root.wingRadius
            y: root.docked ? (root.tabHeight - root.bodyH) : 0
            width: root.tabWidth
            height: root.bodyH
            clip: root.docked
            topLeftRadius: root.docked ? root.effR : height / 2
            topRightRadius: root.docked ? root.effR : height / 2
            bottomLeftRadius: root.docked ? 0 : height / 2
            bottomRightRadius: root.docked ? 0 : height / 2
            color: Theme.popBg
            border.width: root.docked ? 0 : 1
            border.color: Theme.rim

            // 3-sided 1px rim in docked Frame mode (bottom fuses into frame strip).
            Shape {
                anchors.fill: parent
                visible: root.docked && root.bodyH >= 2 && root.width >= 4
                preferredRendererType: Shape.CurveRenderer
                antialiasing: true

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Theme.rim
                    strokeWidth: 1
                    capStyle: ShapePath.FlatCap

                    startX: 0.5
                    startY: root.bodyH - root.wingR

                    PathLine {
                        x: 0.5
                        y: root.effR
                    }

                    PathArc {
                        x: root.effR
                        y: 0.5
                        radiusX: Math.max(0.5, root.effR - 0.5)
                        radiusY: Math.max(0.5, root.effR - 0.5)
                        useLargeArc: false
                        direction: PathArc.Clockwise
                    }

                    PathLine {
                        x: root.tabWidth - root.effR
                        y: 0.5
                    }

                    PathArc {
                        x: root.tabWidth - 0.5
                        y: root.effR
                        radiusX: Math.max(0.5, root.effR - 0.5)
                        radiusY: Math.max(0.5, root.effR - 0.5)
                        useLargeArc: false
                        direction: PathArc.Clockwise
                    }

                    PathLine {
                        x: root.tabWidth - 0.5
                        y: root.bodyH - root.wingR
                    }
                }
            }

            Item {
                id: inner
                x: 0
                y: root.bodyH - root.tabHeight
                width: root.tabWidth
                height: root.tabHeight
            }
        }
    }
}
