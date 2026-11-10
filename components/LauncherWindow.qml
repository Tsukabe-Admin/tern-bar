import QtQuick
import Quickshell
import Quickshell.Wayland
import "../singletons"

// The launcher card. Drops down under the pill it was opened from, on that
// pill's screen. One full-screen transparent overlay surface: it holds the
// keyboard while open, and a click outside the card closes it.
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

    screen: Popups.screenNamed(Launcher.screenName)
    visible: Launcher.open
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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Explicit geometry, not `item: card` — a Region keeps the geometry it
    // last saw (see PillRegion.qml), and the card's height follows the results.
    BackgroundEffect.blurRegion: Region {
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        radius: card.radius
    }

    onVisibleChanged: {
        if (!win.visible)
            return;
        search.text = Launcher.query;
        search.cursorPosition = search.text.length;
        search.forceActiveFocus();
        win.selected = 0;
        openAnim.restart();
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
        anchors.fill: parent
        onClicked: Launcher.close()
    }

    Rectangle {
        id: card

        width: 560
        height: column.implicitHeight + 16
        x: Math.max(12, Math.min(Launcher.anchorX, win.width - card.width - 12))
        y: Theme.barMarginTop + Theme.barHeight + 6
        radius: Theme.radiusCard
        color: Theme.popBg
        border.width: 1
        border.color: Theme.rim
        transformOrigin: Item.Top

        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Theme.motionFast; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "scale"; from: 0.97; to: 1; duration: Theme.motionFast; easing.type: Easing.OutCubic }
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
}
