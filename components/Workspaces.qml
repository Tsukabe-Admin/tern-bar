pragma ComponentBehavior: Bound

import QtQuick
import "../singletons"

// Workspace chips for one output, ordered by idx. Clicking focuses by
// workspace Id (indices collide across outputs); the wheel steps to the
// workspace above or below. niri always keeps one empty workspace at the end
// of each output: its chip is left out unless it is the active one, and
// scrolling down from the last chip still reaches it. On Hyprland, a
// scratchpad (special workspace) open on this output adds one more chip,
// which hides it again.
//
// Classic Tern draws the chips alone, each a BarItem. Tern Frame draws them
// "connected": a strip joins neighbouring occupied workspaces, and a capsule
// slides to the active one (accent on the focused monitor), with that chip's
// glyph redrawn on top of it in Theme.accentInk.
Item {
    id: root

    property string output: ""

    readonly property bool connected: Theme.isFramed

    readonly property var all: Compositor.workspacesFor(root.output)
    readonly property var shown: root.all.filter((ws, i) => !(Compositor.isNiri && i === root.all.length - 1
        && ws.active_window_id === null && !ws.is_active))
    readonly property string special: Compositor.specialWorkspaceOn(root.output)

    readonly property int activeIdx: {
        const focused = root.shown.findIndex((ws) => ws.is_focused);
        if (focused !== -1)
            return focused;
        return root.shown.findIndex((ws) => ws.is_active);
    }
    readonly property bool monitorFocused: root.shown.some((ws) => ws.is_focused)

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    property real animLeft: 0
    property real animRight: 0
    property bool capsuleInitialized: false
    property int lastSyncedIdx: -1
    readonly property int fastDuration: Looks.calmMotion ? 180 : 210
    readonly property int slowDuration: Math.round(root.fastDuration * 1.5)

    function glyphFor(ws) {
        return ws.is_urgent ? "󰀦"
            : ws.is_focused ? "󰮯"
            : ws.is_active ? "󰊠"
            : "•";
    }

    function isOccupied(ws) {
        return ws !== null && ws !== undefined && ws.active_window_id !== null && ws.active_window_id !== undefined;
    }

    // Moves the capsule to the active chip. Called when the Row has placed its
    // chips: every workspace event rebuilds them, and a chip that has just
    // been made still sits at x 0 until then. Moving to another workspace
    // stretches (the leading edge arrives first); a chip that only changed
    // its place or width is followed evenly.
    function syncActiveCapsule() {
        const item = (root.connected && root.activeIdx >= 0 && root.activeIdx < wsRepeater.count)
            ? wsRepeater.itemAt(root.activeIdx) : null;
        if (!item || item.width <= 0) {
            leftAnim.stop();
            rightAnim.stop();
            root.animLeft = 0;
            root.animRight = 0;
            root.capsuleInitialized = false;
            root.lastSyncedIdx = -1;
            return;
        }

        const targetLeft = item.x;
        const targetRight = item.x + item.width;
        const indexChanged = root.activeIdx !== root.lastSyncedIdx;

        if (!root.capsuleInitialized || Looks.restyling || root.lastSyncedIdx < 0) {
            leftAnim.stop();
            rightAnim.stop();
            leftAnim.to = targetLeft;
            rightAnim.to = targetRight;
            root.animLeft = targetLeft;
            root.animRight = targetRight;
            root.capsuleInitialized = true;
            root.lastSyncedIdx = root.activeIdx;
            return;
        }

        // Already there, or already on its way there.
        if (Math.abs(targetLeft - leftAnim.to) < 0.5 && Math.abs(targetRight - rightAnim.to) < 0.5 && !indexChanged)
            return;

        const movingRight = targetLeft > root.animLeft || (Math.abs(targetLeft - root.animLeft) < 0.5 && targetRight > root.animRight);
        leftAnim.stop();
        rightAnim.stop();
        if (indexChanged) {
            leftAnim.duration = movingRight ? root.slowDuration : root.fastDuration;
            rightAnim.duration = movingRight ? root.fastDuration : root.slowDuration;
        } else {
            leftAnim.duration = root.fastDuration;
            rightAnim.duration = root.fastDuration;
        }
        leftAnim.to = targetLeft;
        rightAnim.to = targetRight;
        leftAnim.start();
        rightAnim.start();
        root.lastSyncedIdx = root.activeIdx;
    }

    onConnectedChanged: root.syncActiveCapsule()

    NumberAnimation {
        id: leftAnim
        target: root
        property: "animLeft"
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveSpatialFast
    }

    NumberAnimation {
        id: rightAnim
        target: root
        property: "animRight"
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveSpatialFast
    }

    // Wheel up: the workspace above; wheel down: the one below.
    function step(delta) {
        if (scrollCooldown.running)
            return;
        const i = root.all.findIndex((ws) => ws.is_active);
        const j = i + (delta > 0 ? -1 : 1);
        if (i === -1 || j < 0 || j >= root.all.length)
            return;
        Compositor.focusWorkspace(root.all[j].id);
        scrollCooldown.restart();
    }

    // A touchpad swipe sends many wheel events: one step per 200 ms.
    Timer {
        id: scrollCooldown
        interval: 200
    }

    // Tern Frame, back layer: one strip uniting adjacent occupied workspaces.
    Item {
        anchors.fill: row
        visible: root.connected

        Repeater {
            model: root.connected ? root.shown : []

            delegate: Rectangle {
                id: occSeg
                required property var modelData
                required property int index

                readonly property Item chip: occSeg.index < wsRepeater.count ? wsRepeater.itemAt(occSeg.index) : null
                readonly property bool occupied: root.isOccupied(occSeg.modelData)
                readonly property bool prevOccupied: occSeg.index > 0 && root.isOccupied(root.shown[occSeg.index - 1])
                readonly property bool nextOccupied: occSeg.index + 1 < root.shown.length && root.isOccupied(root.shown[occSeg.index + 1])

                x: occSeg.chip ? occSeg.chip.x : 0
                y: 0
                width: occSeg.chip ? occSeg.chip.width : 0
                height: parent.height
                visible: occSeg.occupied && occSeg.chip !== null && occSeg.chip.width > 0
                color: Theme.hover

                topLeftRadius: occSeg.prevOccupied ? 0 : Theme.itemRadius
                bottomLeftRadius: occSeg.prevOccupied ? 0 : Theme.itemRadius
                topRightRadius: occSeg.nextOccupied ? 0 : Theme.itemRadius
                bottomRightRadius: occSeg.nextOccupied ? 0 : Theme.itemRadius
            }
        }
    }

    readonly property real capsuleLeft: Math.min(root.animLeft, root.animRight)
    readonly property real capsuleWidth: Math.max(0, Math.abs(root.animRight - root.animLeft))
    readonly property bool hasCapsule: root.connected && root.activeIdx >= 0 && root.shown.length > 0
        && root.capsuleWidth > 0

    // Tern Frame: the active workspace on a monitor that does not have the
    // focus. Behind `row`, so the row's own glyph stays crisp on Theme.l3.
    Rectangle {
        x: root.capsuleLeft
        y: 0
        width: root.capsuleWidth
        height: row.height
        z: 0
        radius: Theme.itemRadius
        visible: root.hasCapsule && activeCapsule.opacity < 0.999
        color: Theme.l3
    }

    // Tern Frame: the focused workspace. An opaque accent capsule above `row`
    // with the glyphs redrawn inside it in Theme.accentInk, clipped to the
    // capsule and faded as a whole, so the translucent Theme.l3 never shows
    // behind an accentInk glyph (animating the colour itself did that).
    Rectangle {
        id: activeCapsule

        x: root.capsuleLeft
        y: 0
        width: root.capsuleWidth
        height: row.height
        z: 1
        radius: Theme.itemRadius
        visible: root.hasCapsule && activeCapsule.opacity > 0
        opacity: root.monitorFocused ? 1 : 0
        color: Theme.accent
        clip: true

        Behavior on opacity {
            enabled: !Looks.restyling
            NumberAnimation {
                duration: Theme.motionFast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveEffects
            }
        }

        Item {
            x: -activeCapsule.x
            y: 0
            width: row.width
            height: row.height

            Repeater {
                model: root.connected ? root.shown : []

                delegate: Item {
                    id: overlayChip
                    required property var modelData
                    required property int index

                    readonly property Item chip: overlayChip.index < wsRepeater.count ? wsRepeater.itemAt(overlayChip.index) : null

                    x: overlayChip.chip ? overlayChip.chip.x : 0
                    y: 0
                    width: overlayChip.chip ? overlayChip.chip.width : 0
                    height: overlayChip.chip ? overlayChip.chip.height : 0

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: root.glyphFor(overlayChip.modelData)
                        color: overlayChip.modelData.is_urgent ? Theme.bad : Theme.accentInk
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                }
            }
        }
    }

    // Classic Tern: a chip is a plain bar item, coloured by its state.
    Component {
        id: classicChip

        BarItem {
            required property var modelData

            text: root.glyphFor(modelData)
            fg: modelData.is_urgent ? Theme.bad
                : modelData.is_focused ? Theme.accent
                : modelData.is_active ? Theme.t2
                : Theme.t3
            onClicked: Compositor.focusWorkspace(modelData.id)
            onScrolled: (delta) => root.step(delta)
        }
    }

    // Tern Frame: a fixed-width chip (the capsule aims at it, so it must not
    // glide), brighter where a workspace has windows, with no hover fill
    // under the focused capsule.
    Component {
        id: connectedChip

        Item {
            id: chip
            required property var modelData

            readonly property int sidePadding: 9

            implicitWidth: chipLabel.implicitWidth + 2 * chip.sidePadding
            implicitHeight: Theme.pillHeight - 2 * Theme.pillPadding

            Rectangle {
                anchors.fill: parent
                radius: Theme.itemRadius
                color: Theme.hover
                opacity: (!chip.modelData.is_focused && (chipHover.hovered || chipTap.pressed)) ? 1 : 0

                Behavior on opacity {
                    enabled: !Looks.restyling
                    NumberAnimation {
                        duration: Theme.motionFast
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Text {
                id: chipLabel
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.glyphFor(chip.modelData)
                color: chip.modelData.is_urgent ? Theme.bad
                    : chip.modelData.is_focused ? Theme.accent
                    : chip.modelData.is_active ? Theme.t1
                    : root.isOccupied(chip.modelData) ? Theme.t2
                    : Theme.t3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            HoverHandler {
                id: chipHover
            }

            TapHandler {
                id: chipTap
                acceptedButtons: Qt.LeftButton
                onTapped: Compositor.focusWorkspace(chip.modelData.id)
            }

            // A MouseArea, not a WheelHandler: see BarItem.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: (wheel) => root.step(wheel.angleDelta.y > 0 ? 1 : -1)
            }
        }
    }

    Row {
        id: row
        z: 0
        spacing: 0

        onPositioningComplete: root.syncActiveCapsule()

        Repeater {
            id: wsRepeater
            model: root.shown
            delegate: root.connected ? connectedChip : classicChip
        }

        BarItem {
            visible: root.special !== ""
            text: "󰌨"
            fg: Theme.accent
            onClicked: Compositor.toggleSpecialWorkspace(root.special)
        }
    }
}
