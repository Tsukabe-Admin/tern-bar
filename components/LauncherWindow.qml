import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import "../singletons"
import "../singletons/looks.js" as LooksLib

// The launcher card. Drops down under the pill it was opened from, on that
// pill's screen. One full-screen transparent overlay surface: it holds the
// keyboard while open, and a click outside the card closes it.
//
// In Tern Frame the card is attached to the frame's top lip: it grows out of
// it and, after closing, retracts into it (the window stays mapped for that
// moment, without keyboard or pointer). Over a fullscreen window the frame is
// hidden under that window, so there the card floats as in Classic Tern.
//
// Keys: type to search · Up/Down, Tab/Shift+Tab, Ctrl+N/Ctrl+P move ·
// Enter opens · Esc clears the search, then closes.
PanelWindow {
    id: win

    property int selected: 0
    // How a rebuilt list finds the selection again: the selected row's key, and
    // the search (mode and text) the list was last built for.
    property string selectedKey: ""
    property string builtFor: ""
    readonly property int rowHeight: 44
    readonly property int maxRows: 8

    onSelectedChanged: win.rememberSelection()

    function rememberSelection() {
        const row = Launcher.results[win.selected];
        win.selectedKey = row ? row.key : "";
    }

    // Mapped: while the launcher is open, and in Tern Frame for the moment
    // its card takes to retract afterwards.
    property bool shown: false
    readonly property bool attached: Theme.isFramed && !Compositor.isOutputFullscreen(Launcher.screenName)

    screen: Popups.screenNamed(Launcher.screenName)
    visible: win.shown
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "tern-bar-launcher"
    WlrLayershell.keyboardFocus: Launcher.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Region {
        id: noInput
    }
    mask: Launcher.open ? null : noInput

    property real openReveal: 1.0
    property bool mappedReady: false
    // The card's full height while the launcher was last open. Closing empties
    // the list, and the card must not shrink to that while it retracts.
    property real openHeight: 0

    Component.onCompleted: if (Launcher.open) win.shown = true

    // Explicit geometry, not `item: card` — a Region keeps the geometry it
    // last saw (see PillRegion.qml). Disabled in Frame Look so curved wings
    // never show rectangular Wayland blur slabs.
    Region {
        id: classicBlur
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        radius: Theme.radiusCard
    }
    BackgroundEffect.blurRegion: Theme.isFramed ? null : classicBlur

    function syncLauncherCut() {
        if (win.attached && win.visible && win.mappedReady && card.height >= 2) {
            const wing = card.wingR >= 2 ? card.wingR : 0;
            Launcher.activeCutLeft = card.x - wing;
            Launcher.activeCutRight = card.x + card.width + wing;
            Launcher.activeCutX = card.x;
            Launcher.activeCutWidth = card.width;
            Launcher.activeCutHeight = card.height;
            Launcher.activeCutRadius = card.effR;
            Launcher.activeCutWing = wing;
        } else {
            Launcher.activeCutLeft = 0;
            Launcher.activeCutRight = 0;
            Launcher.activeCutX = 0;
            Launcher.activeCutWidth = 0;
            Launcher.activeCutHeight = 0;
            Launcher.activeCutRadius = 0;
            Launcher.activeCutWing = 0;
        }
    }

    function startReveal() {
        revealFallback.stop();
        if (!win.visible || win.mappedReady)
            return;
        win.mappedReady = true;
        win.reveal();
    }

    function reveal() {
        openAnim.stop();
        frameOpenAnim.stop();
        frameCloseAnim.stop();
        if (win.attached)
            frameOpenAnim.restart();
        else
            openAnim.restart();
    }

    // A fresh opening: the field, the selection, and the card as it is before
    // its reveal.
    function prepare() {
        search.text = Launcher.query;
        search.cursorPosition = search.text.length;
        search.forceActiveFocus();
        win.selected = 0;
        openAnim.stop();
        frameOpenAnim.stop();
        frameCloseAnim.stop();
        if (win.attached) {
            win.openReveal = 0;
            card.opacity = 1;
            card.scale = 1.0;
            column.opacity = 0;
        } else {
            win.openReveal = 1.0;
            card.opacity = 0;
            column.opacity = 1;
        }
    }

    Timer {
        id: revealFallback
        interval: 80
        repeat: false
        onTriggered: win.startReveal()
    }

    Connections {
        target: backdrop.Window.window
        function onFrameSwapped() {
            win.startReveal();
        }
    }

    onVisibleChanged: {
        win.mappedReady = false;
        win.syncLauncherCut();
        if (!win.visible) {
            revealFallback.stop();
            openAnim.stop();
            frameOpenAnim.stop();
            frameCloseAnim.stop();
            return;
        }
        win.prepare();
        revealFallback.restart();
    }

    // A popup that opens while the card retracts takes the lip at once: the
    // frame has one cut-out at the top.
    Connections {
        target: Popups
        function onOpenChanged() {
            if (Popups.open !== "" && !Launcher.open)
                win.shown = false;
        }
    }

    // The action waiting for its second Enter is always the selected row. It is
    // selected when it is armed (a click arms too), it stays selected when the
    // list is rebuilt under it (in a search that happens every time a window
    // opens, closes or renames itself), and moving the selection or typing
    // withdraws the confirmation. So Enter can only ever confirm the row that is
    // shown in red.
    Connections {
        target: Launcher

        function onArmedChanged() {
            win.selectArmed();
        }

        function onOpenChanged() {
            if (Launcher.open) {
                win.openHeight = card.targetHeight;
                if (!win.shown) {
                    win.shown = true;   // onVisibleChanged prepares and reveals
                } else {                // reopened while the card was retracting
                    win.prepare();
                    win.reveal();
                }
            } else if (win.shown && win.attached && win.mappedReady && !Looks.restyling) {
                frameOpenAnim.stop();
                column.opacity = 0;
                frameCloseAnim.restart();
            } else {
                win.shown = false;
            }
        }

        // The list is rebuilt for a new search, and also under an unchanged one:
        // a window opens, closes or renames itself, the clipboard history
        // arrives. A new search starts at the top. The same search keeps the
        // selection on its row, wherever that row is now, so Enter opens what
        // was selected and not whatever moved into its place.
        function onResultsChanged() {
            const builtNow = Launcher.mode + "\n" + Launcher.query;
            const sameSearch = builtNow === win.builtFor;
            win.builtFor = builtNow;
            if (!win.selectArmed()) {
                const at = sameSearch
                    ? Launcher.results.findIndex((row) => row.key === win.selectedKey) : -1;
                win.selected = Math.max(0, at);
                if (at > 0)
                    list.positionViewAtIndex(at, ListView.Contain);
                else
                    list.positionViewAtBeginning();
            }
            win.rememberSelection();
        }

        // The field shows the launcher's search. Typing sets the search from the
        // field (onTextChanged below); the clipboard and power shortcuts set it
        // from outside while the card is open, and then the field has to follow.
        function onQueryChanged() {
            if (search.text === Launcher.query)
                return;
            search.text = Launcher.query;
            search.cursorPosition = search.text.length;
        }
    }

    // Selects the armed power action. False when nothing is armed or it is not listed.
    function selectArmed() {
        if (Launcher.armed === "")
            return false;
        const at = Launcher.results.findIndex((row) => row.kind === "power" && row.action === Launcher.armed);
        if (at === -1)
            return false;
        win.selected = at;
        list.positionViewAtIndex(at, ListView.Contain);
        return true;
    }

    function move(step) {
        const n = Launcher.results.length;
        if (n === 0)
            return;
        Launcher.unarm();
        win.selected = (win.selected + step + n) % n;
        list.positionViewAtIndex(win.selected, ListView.Contain);
    }

    MouseArea {
        id: backdrop
        anchors.fill: parent
        onClicked: Launcher.close()
    }

    AttachedShadow {
        id: launcherShadow
        readonly property real pad: Theme.frameShadowExtent
        readonly property real wing: card.wingR >= 2 ? card.wingR : 0
        readonly property real minX: Theme.frameThickness
        readonly property real maxX: Math.max(minX, win.width - Theme.frameThickness)
        readonly property real maxY: Math.max(Theme.barHeight, win.height - Theme.frameThickness)
        readonly property real leftX: Math.max(minX, card.x - wing - pad)
        readonly property real rightX: Math.min(maxX, card.x + card.width + wing + pad)
        readonly property real bottomY: Math.min(maxY, card.y + card.height + pad)

        x: leftX
        y: Theme.barHeight
        width: Math.max(0, rightX - leftX)
        height: Math.max(0, bottomY - Theme.barHeight)
        visible: win.attached && Theme.frameShadowEnabled && win.visible
            && win.mappedReady && card.height >= 2
            && width > 0 && height > 0
        attachRect: Qt.vector4d(card.x, card.y, card.width, card.height)
        attachRadii: Qt.vector4d(card.effR, wing, 0.0, 0.0)
        innerBox: Qt.vector4d(
            Theme.frameThickness, Theme.barHeight,
            win.width - Theme.frameThickness, win.height - Theme.frameThickness)
        shadowParams: Qt.vector4d(
            Theme.frameShadowKeyOpacity, Theme.frameShadowAoOpacity,
            Theme.frameShadowSigma, Theme.frameShadowAoSigma)
        geomParams: Qt.vector4d(
            Theme.innerRounding, Theme.frameShadowOffsetY,
            pad, 0.0)
        cutSpan: Qt.vector4d(
            Launcher.activeCutRight > Launcher.activeCutLeft ? 1.0 : 0.0,
            Launcher.activeCutLeft,
            Launcher.activeCutRight,
            0.0)
    }

    ConcaveCorner {
        corner: "topRight"
        visible: win.attached && win.visible && card.wingR >= 2
        x: card.x - card.wingR
        y: card.y
        radius: card.wingR
        fillColor: Theme.popBg
        strokeColor: Theme.rim
    }

    ConcaveCorner {
        corner: "topLeft"
        visible: win.attached && win.visible && card.wingR >= 2
        x: card.x + card.width
        y: card.y
        radius: card.wingR
        fillColor: Theme.popBg
        strokeColor: Theme.rim
    }

    Rectangle {
        id: card

        readonly property real targetHeight: column.implicitHeight + 16
        readonly property real fullHeight: Launcher.open ? card.targetHeight : win.openHeight
        readonly property real effR: Math.max(1,
            Math.min(Theme.radiusCard, height * 0.5, width * 0.5))
        readonly property real wingR: win.attached
            ? Math.min(Theme.wingRadius, Math.max(0, height - effR)) : 0
        readonly property real frameMinX: Theme.frameThickness + Theme.innerRounding + Theme.wingRadius
        readonly property real frameMaxX: Math.max(frameMinX + width, win.width - frameMinX)

        onTargetHeightChanged: if (Launcher.open) win.openHeight = card.targetHeight

        width: 560
        height: win.attached
            ? Math.round(card.fullHeight * win.openReveal)
            : card.targetHeight
        x: Theme.isFramed
            ? (Launcher.anchorCenterX >= 0
                ? LooksLib.clampDrawerX(Launcher.anchorCenterX, width, card.frameMinX, card.frameMaxX)
                : Math.round((win.width - width) / 2))
            : Math.max(12, Math.min(Launcher.anchorX, win.width - card.width - 12))
        y: win.attached ? Theme.barHeight : (Theme.barMarginTop + Theme.barHeight + 6)
        topLeftRadius: win.attached ? 0 : Theme.radiusCard
        topRightRadius: win.attached ? 0 : Theme.radiusCard
        bottomLeftRadius: Theme.radiusCard
        bottomRightRadius: Theme.radiusCard
        color: Theme.popBg
        border.width: win.attached ? 0 : 1
        border.color: Theme.rim
        clip: win.attached
        transformOrigin: Item.Top

        onXChanged: win.syncLauncherCut()
        onHeightChanged: win.syncLauncherCut()
        onWingRChanged: win.syncLauncherCut()

        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Theme.motionFast; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "scale"; from: 0.97; to: 1; duration: Theme.motionFast; easing.type: Easing.OutCubic }
        }

        // Attached: the card grows out of the lip, solid, while what is in it
        // fades in...
        ParallelAnimation {
            id: frameOpenAnim
            NumberAnimation {
                target: column
                property: "opacity"
                from: 0
                to: 1
                duration: Theme.motionFast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveEffects
            }
            NumberAnimation {
                target: win
                property: "openReveal"
                from: 0
                to: 1
                duration: Theme.motionBase
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveEffects
            }
        }

        // ...and retracts into it, already empty, before the window goes.
        NumberAnimation {
            id: frameCloseAnim
            target: win
            property: "openReveal"
            to: 0
            duration: Theme.motionBase
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveEffects
            onFinished: if (!Launcher.open) win.shown = false
        }

        // The card's own padding is not "outside".
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 6

            Item {
                width: parent.width
                height: 40

                Text {
                    textFormat: Text.PlainText
                    id: glyph
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: Launcher.mode === "power" ? "\uf011" : "\uf002"
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 2
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: search.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: search.text === ""
                    text: Launcher.mode === "power" ? "Power" : "Search apps and windows     ;  clipboard"
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                }

                TextInput {
                    id: search
                    anchors.left: glyph.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    color: Theme.t1
                    selectionColor: Qt.alpha(Theme.accent, 0.35)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1

                    onTextChanged: Launcher.query = text

                    Keys.onPressed: (event) => {
                        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                        if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab
                                || (ctrl && event.key === Qt.Key_N)) {
                            win.move(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab
                                || (ctrl && event.key === Qt.Key_P)) {
                            win.move(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            // A held key repeats, and a repeat is not a second
                            // Enter: it must not confirm the power action that
                            // the first one armed.
                            if (!event.isAutoRepeat)
                                Launcher.activate(Launcher.results[win.selected]);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            if (search.text !== "" && Launcher.mode !== "power")
                                search.text = "";
                            else
                                Launcher.close();
                            event.accepted = true;
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.l3
            }

            ListView {
                id: list
                width: parent.width
                height: Math.max(1, Math.min(Launcher.results.length, win.maxRows)) * win.rowHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: Launcher.results

                delegate: LauncherRow {
                    selected: index === win.selected
                    onActivated: Launcher.activate(modelData)
                }

                Row {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    spacing: 14

                    AsciiArt {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "drift"
                        tint: Theme.t3
                        playing: win.visible
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: "No matches"
                        color: Theme.t3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }
            }
        }
    }

    // 3-sided 1px rim of the attached card, as an unclipped sibling (the top
    // fuses into the bar lip).
    Shape {
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        visible: win.attached && win.visible && card.height >= 2 && card.width >= 4
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true
        z: 2

        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.rim
            strokeWidth: 1
            capStyle: ShapePath.FlatCap

            startX: 0.5
            startY: card.wingR

            PathLine {
                x: 0.5
                y: card.height - card.effR
            }

            PathArc {
                x: card.effR
                y: card.height - 0.5
                radiusX: Math.max(0.5, card.effR - 0.5)
                radiusY: Math.max(0.5, card.effR - 0.5)
                useLargeArc: false
                direction: PathArc.Counterclockwise
            }

            PathLine {
                x: card.width - card.effR
                y: card.height - 0.5
            }

            PathArc {
                x: card.width - 0.5
                y: card.height - card.effR
                radiusX: Math.max(0.5, card.effR - 0.5)
                radiusY: Math.max(0.5, card.effR - 0.5)
                useLargeArc: false
                direction: PathArc.Counterclockwise
            }

            PathLine {
                x: card.width - 0.5
                y: card.wingR
            }
        }
    }
}
