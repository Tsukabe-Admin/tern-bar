import QtQuick
import Quickshell
import Quickshell.Wayland
import "../singletons"

// The floating desktop pet: one always-on-top layer surface per pet output,
// masked down to the sprite (plus the callout/bubble while shown) so the rest of
// the screen stays clickable.
//
// Drag moves it live; releasing without movement (distance² < 16) clicks through
// to the Tern block; a real drop persists x/y/output through the engine so the pet
// lands in the same place after a reload.
PanelWindow {
    id: pet

    // Screen name the pet should live on ("" / null = the first screen). Layer
    // surfaces cannot be dragged across outputs, so "Move to next screen" is an
    // engine-side setting, not a window move.
    property string screenName: ""

    readonly property var st: Poke.status
    readonly property var conf: (st && st.pet) ? st.pet : ({ enabled: false, size: 96, bubbleAlerts: true })
    readonly property int size: conf.size || 96
    readonly property string outputName: conf.output || ""

    screen: {
        var screens = Quickshell.screens;
        if (!screens || screens.length === 0)
            return null;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === pet.outputName)
                return screens[i];
        }
        return screens[0];
    }

    // Bottom-right default, 24px in from the corner.
    readonly property real defaultX: pet.screen ? pet.screen.width - pet.size - 24 : 0
    readonly property real defaultY: pet.screen ? pet.screen.height - pet.size - 24 : 0
    property real petX: conf.x !== null && conf.x !== undefined ? conf.x : defaultX
    property real petY: conf.y !== null && conf.y !== undefined ? conf.y : defaultY

    // The size (or the output) can change while x/y are still "default": the
    // corner must follow, or a resized sprite hangs off the screen edge. A drag
    // in progress owns the position; the poll must not snap it back.
    property bool dragging: false
    onSizeChanged: if (!pet.dragging) pet.reinitDefaults()
    onScreenChanged: if (!pet.dragging) pet.reinitDefaults()
    onConfChanged: if (!pet.dragging) pet.reinitDefaults()

    // `act pet_move` runs in a fresh engine process, so for a few hundred ms
    // (longer when the engine lock is busy) status.json still carries the old
    // position. A poll landing in that window used to be adopted and the sprite
    // jumped back to where it had been, then jumped forward on the next poll.
    // A pending drop therefore owns the position until the engine echoes the
    // values we sent; the timer is the safety net for a move the engine never
    // persisted (it may answer `busy` after its 30 s lock wait).
    property bool movePending: false
    property real pendingX: 0
    property real pendingY: 0

    Timer {
        id: pendingTimer
        interval: 10000
        onTriggered: {
            pet.movePending = false;
            if (!pet.dragging)
                pet.reinitDefaults();
        }
    }

    function reinitDefaults() {
        var nx = (conf.x !== null && conf.x !== undefined) ? conf.x : pet.defaultX;
        var ny = (conf.y !== null && conf.y !== undefined) ? conf.y : pet.defaultY;
        if (pet.movePending) {
            if (Math.abs(nx - pet.pendingX) >= 0.5 || Math.abs(ny - pet.pendingY) >= 0.5)
                return;              // a poll that read status.json before our write
            pet.movePending = false;
            pendingTimer.stop();
        }
        pet.petX = nx;
        pet.petY = ny;
    }

    // Persist a drop: `x`/`y` are the sprite's work-area coordinates.
    function sendMove(x, y) {
        pet.movePending = true;
        pet.pendingX = x;
        pet.pendingY = y;
        pendingTimer.restart();
        Poke.run(["act", "pet_move", JSON.stringify({
            x: x, y: y, output: pet.screen ? pet.screen.name : ""
        })]);
    }

    // A new alert id shows the bubble for 6 s (upstream FloatingPetPanel TTL).
    property string bubbleAlertId: ""
    property string bubbleTitle: ""
    property string bubbleBody: ""
    property bool bubbleCritical: false
    property bool bubbleShown: false

    // Hover callout state: off entirely when the user turns the tooltip off in the
    // pane's Settings (floatingPetTooltip), and hidden while a bubble shows.
    readonly property bool hoverShown: pet.conf.tooltip !== false && dragArea.containsMouse && !pet.bubbleShown

    // The tooltip ("Today: … tokens") and the alert bubble are wider than the
    // sprite, so the surface carries a fixed 160px of room on each side of it and
    // both rows are centred directly under the sprite (clamped to the screen when
    // the pet hugs an edge). The geometry never changes — not with hover, not with
    // petX: growing it on hover made niri re-place the surface, which pushed the
    // sprite out from under the pointer and flickered at ~120 Hz. The room around the
    // sprite is kept click-through by the input mask below.
    readonly property real side: 160
    readonly property real spriteX: pet.side
    readonly property real surfaceW: pet.size + 2 * pet.side
    readonly property real calloutW: Math.min(pet.surfaceW, Math.max(pet.size, hoverText.implicitWidth + 16))
    readonly property real bubbleW: Math.max(pet.size, 220)

    // Left edge, in surface coordinates, of a row `w` wide centred under the sprite
    // and kept inside the screen (the surface itself may hang past an edge).
    function rowLeft(w) {
        var x = pet.spriteX + (pet.size - w) / 2;
        var screenLeft = pet.petX - pet.side;
        var lo = Math.max(0, -screenLeft);
        var hi = pet.surfaceW - w;
        if (pet.screen)
            hi = Math.min(hi, pet.screen.width - w - screenLeft);
        return Math.max(lo, Math.min(Math.max(lo, hi), x));
    }
    readonly property real calloutX: pet.rowLeft(pet.calloutW)
    readonly property real bubbleX: pet.rowLeft(pet.bubbleW)

    anchors.top: true
    anchors.left: true
    margins.top: pet.petY
    margins.left: pet.petX - pet.side
    implicitWidth: pet.surfaceW
    implicitHeight: pet.size + 72
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay

    // Only the sprite — plus the tooltip/bubble rows while they are shown — takes
    // input; the rest of the fixed surface stays transparent to clicks.
    mask: Region {
        Region { item: spriteItem }
        Region {
            x: pet.calloutX
            y: pet.size
            width: pet.hoverShown ? pet.calloutW : 0
            height: pet.hoverShown ? 22 : 0
        }
        Region {
            x: pet.bubbleX
            y: pet.size
            width: pet.bubbleShown ? pet.bubbleW : 0
            height: pet.bubbleShown ? 72 : 0
        }
    }

    // Alert bubbles: each alert id is shown once. `lastAlert` stays in runtime.json until
    // the next alert fires, so the alert already stored when the pet first sees a status
    // counts as seen (a bar reload or a pet toggle must not replay it). An id is marked
    // seen even when bubbles are off, so switching them on later does not show it either.
    // Reads `st` directly: this runs while the component is still being built, before
    // the `conf` binding is usable.
    property bool alertSeeded: false

    function noteAlert() {
        var s = pet.st;
        if (!s)
            return;
        var alert = s.alert;
        var id = (alert && alert.id) ? alert.id : "";
        if (!pet.alertSeeded) {
            pet.alertSeeded = true;
            pet.bubbleAlertId = id;
            return;
        }
        if (id === "" || id === pet.bubbleAlertId)
            return;
        pet.bubbleAlertId = id;
        if (!s.pet || s.pet.bubbleAlerts === false)
            return;
        pet.bubbleTitle = alert.title || "Limit";
        pet.bubbleBody = alert.body || "";
        pet.bubbleCritical = !!alert.critical;
        pet.bubbleShown = true;
        bubbleTimer.restart();
    }

    Component.onCompleted: pet.noteAlert()
    onStChanged: pet.noteAlert()

    Timer {
        id: bubbleTimer
        interval: 6000
        repeat: false
        onTriggered: pet.bubbleShown = false
    }

    PokeSprite {
        id: spriteItem
        x: pet.spriteX
        y: 0
        width: pet.size
        height: pet.size
        sprite: pet.st ? (pet.st.sprite || "") : ""
        still: pet.st ? (pet.st.still || "") : ""
        frameFloorMs: pet.st ? (pet.st.frameFloorMs || 400) : 400

        MouseArea {
            id: dragArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true

            property real lastX: 0
            property real lastY: 0
            property real moved: 0

            onPressed: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                            petMenu.openFor(dragArea);
                    return;
                }
                // The window moves with the pointer, so each event's local
                // coordinate is (pointer travel - window travel). Applying the
                // *incremental* local delta keeps the two in lockstep; applying
                // the cumulative one makes the sprite fly past the pointer.
                pet.dragging = true;
                lastX = mouse.x;
                lastY = mouse.y;
                moved = 0;
            }
            onPositionChanged: (mouse) => {
                // Only a left drag moves the pet. Qt reports button == NoButton on move
                // events, so checking `mouse.button === Qt.RightButton` here never
                // matched: a right-drag (menu open) dragged the sprite by the stale
                // lastX/lastY and followed the pointer, and a right release persists
                // nothing, so the next poll snapped the sprite back. `pet.dragging` is
                // only set by a left press.
                if (!pet.dragging)
                    return;
                var dx = mouse.x - lastX;
                var dy = mouse.y - lastY;
                moved += Math.abs(dx) + Math.abs(dy);
                pet.petX += dx;
                pet.petY += dy;
                lastX = mouse.x;
                lastY = mouse.y;
            }
            onReleased: (mouse) => {
                if (mouse.button === Qt.RightButton)
                    return;
                pet.dragging = false;
                if (moved * moved < 16) {
                    Poke.open("");
                } else {
                    pet.sendMove(Math.round(pet.petX), Math.round(pet.petY));
                }
            }
        }
    }

    // Hover callout ("Today: … tokens (limit NN%)"), hidden while a bubble shows.
    Item {
        id: hoverRect
        visible: pet.hoverShown
        x: pet.calloutX
        y: pet.size
        width: pet.calloutW
        height: 22

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: Theme.popBg
            border.width: 1
            border.color: Theme.rim

            Text {
                textFormat: Text.PlainText
                id: hoverText
                anchors.centerIn: parent
                text: pet.st ? (pet.st.hover || "") : ""
                color: Theme.t2
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                font.bold: true
            }
        }
    }

    // Alert bubble: title (red when critical) + 2 lines of body, 6 s.
    Item {
        id: bubbleRect
        visible: pet.bubbleShown
        x: pet.bubbleX
        y: pet.size
        width: pet.bubbleW
        height: 72

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Theme.popBg
            border.width: 1
            border.color: pet.bubbleCritical ? Theme.bad : Theme.rim

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 2

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: pet.bubbleTitle
                    color: pet.bubbleCritical ? Theme.bad : Theme.warn
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    height: parent.height - 18
                    text: pet.bubbleBody
                    color: Theme.t1
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
            }

            TapHandler {
                onTapped: pet.bubbleShown = false
            }
        }
    }

    // Right-click menu (same popup recipe as TrayMenu: backstop + card).
    PopupWindow {
        id: petMenu

        property Item anchorItem: null
        readonly property point anchorPos: petMenu.anchorItem
            ? petMenu.anchorItem.mapToItem(null, 0, 0) : Qt.point(0, 0)

        function openFor(item) {
            petMenu.anchorItem = item;
            petMenu.anchor.window = pet;
            petMenu.anchor.rect.x = 0;
            petMenu.anchor.rect.y = 0;
            petMenu.anchor.rect.width = 1;
            petMenu.anchor.rect.height = 1;
            petMenu.visible = true;
        }

        function trigger(action) {
            switch (action) {
            case "open":
                Poke.open("");
                break;
            case "next":
                var screens = Quickshell.screens;
                var idx = 0;
                for (var i = 0; i < screens.length; i++) {
                    if (pet.screen && screens[i].name === pet.screen.name)
                        idx = i;
                }
                var next = screens.length > 0 ? screens[(idx + 1) % screens.length] : null;
                Poke.run(["act", "pet_move", JSON.stringify({
                    x: null, y: null, output: next ? next.name : ""
                })]);
                break;
            case "off":
                Poke.run(["act", "pet_toggle"]);
                break;
            }
            petMenu.visible = false;
        }

        visible: false
        grabFocus: false
        color: "transparent"
        implicitWidth: (pet.screen ? pet.screen.width : 1000)
        implicitHeight: (pet.screen ? pet.screen.height : 1000)

        MouseArea {
            anchors.fill: parent
            enabled: petMenu.visible
            onClicked: petMenu.visible = false
        }

        Rectangle {
            id: petCard
            // This popup is anchored to the screen's top-left corner (the layer
            // anchor is ignored by niri for a popup under a margins-positioned
            // panel), so the card is placed from the pet's own screen position:
            // petX/petY are work-area coordinates, i.e. offset by the bar.
            x: Math.max(0, Math.min(pet.petX, petMenu.width - width))
            y: Math.max(0, Math.min(Theme.workAreaTop + pet.petY + pet.size, petMenu.height - height))
            width: 220
            height: petContent.implicitHeight + 16
            color: Theme.popBg
            radius: Theme.itemRadius
            border.width: 1
            border.color: Theme.rim

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: petContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 8

                Repeater {
                    model: [
                        { text: "Open PokeToken", action: "open" },
                        { text: "Move to next screen", action: "next" },
                        { text: "Turn off floating pet", action: "off" }
                    ]

                    delegate: Item {
                        required property var modelData
                        width: petContent.width
                        height: 30

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 6
                            color: petRowHover.hovered ? Theme.hover : "transparent"
                        }

                        Text {
                            textFormat: Text.PlainText
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.text
                            color: Theme.t1
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }

                        HoverHandler {
                            id: petRowHover
                        }

                        TapHandler {
                            onTapped: petMenu.trigger(modelData.action)
                        }
                    }
                }
            }
        }
    }
}
