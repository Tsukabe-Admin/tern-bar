import QtQuick
import Quickshell
import Quickshell.Wayland
import "../singletons"

// A question in a small window under the bar: an icon and a title, a message,
// an optional big code, an optional text field, and two buttons. The Bluetooth
// pairing questions (BluetoothPrompt) and the Wi-Fi password (WifiPrompt) are
// built on it. One window for the whole shell, on the screen `screenName`.
//
// Only a question that needs typing (`typed`) takes the keyboard, and its
// Enter counts only once the question has been up for half a second and the
// key is not a held key repeating. Other questions are answered with the
// mouse: a key meant for something else must never answer them.
PanelWindow {
    id: win

    // Any new value is a new question: the field starts empty and Enter waits.
    property var token: null
    property bool open: false
    property string screenName: ""
    property string glyph: ""
    property string title: ""
    property string message: ""
    // A code shown big (a number to compare, a code to type elsewhere), and a
    // small line under it.
    property string code: ""
    property string codeNote: ""
    property bool typed: false
    // A password: shown as dots, with a Show/Hide button.
    property bool secret: false
    property int maxLength: 16
    // What the field lets through while typing, and what can be sent.
    property var inputPattern: /.*/
    property var accept: (text) => true
    property string primaryText: ""
    property string secondaryText: "Cancel"
    property string layerNamespace: "tern-bar-prompt"

    readonly property bool ready: !win.typed || win.accept(field.text)
    property bool keysArmed: false
    property bool revealed: false

    signal primary(string text)
    signal secondary

    screen: Popups.screenNamed(win.screenName)
    visible: win.open
    anchors.top: true
    margins.top: Theme.barMarginTop + Theme.barHeight + 12
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: card.width
    implicitHeight: card.height
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: win.layerNamespace
    WlrLayershell.keyboardFocus: win.typed ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // A new question. `typed` is bound to the same change from outside and may
    // not have caught up yet while this runs, so the field takes the focus a
    // moment later, once it has.
    onTokenChanged: {
        win.keysArmed = false;
        win.revealed = false;
        field.text = "";
        armTimer.restart();
        Qt.callLater(() => {
            if (win.typed)
                field.forceActiveFocus();
        });
    }

    // The primary button and Enter: only an answer that can be sent.
    function answer() {
        if (win.ready)
            win.primary(field.text);
    }

    Timer {
        id: armTimer
        interval: 500
        onTriggered: win.keysArmed = true
    }

    Rectangle {
        id: card
        width: 380
        height: col.implicitHeight + 32
        radius: Theme.radiusCard
        color: Theme.popBg
        border.width: 1
        border.color: Theme.rim

        Column {
            id: col
            x: 16
            y: 16
            width: card.width - 32
            spacing: 12

            Row {
                width: parent.width
                spacing: 10

                Text {
                    textFormat: Text.PlainText
                    text: win.glyph
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 2
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width - 30
                    text: win.title
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: Theme.t1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }
            }

            Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                text: win.message
                color: Theme.t2
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                textFormat: Text.PlainText
                visible: win.code !== ""
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: win.code
                color: Theme.t1
                font.family: Theme.fontFamily
                font.pixelSize: 28
                font.bold: true
                font.letterSpacing: 2
            }

            Text {
                textFormat: Text.PlainText
                visible: win.codeNote !== ""
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: win.codeNote
                color: Theme.t3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }

            Row {
                visible: win.typed
                width: parent.width
                spacing: 8

                Rectangle {
                    width: parent.width - (revealChip.visible ? revealChip.width + parent.spacing : 0)
                    height: 34
                    radius: height / 2
                    color: Theme.popBg
                    border.width: 1
                    border.color: field.activeFocus ? Theme.accent : Theme.rim

                    TextInput {
                        id: field
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: Theme.t1
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        maximumLength: win.maxLength
                        echoMode: (win.secret && !win.revealed) ? TextInput.Password : TextInput.Normal
                        validator: RegularExpressionValidator {
                            regularExpression: win.inputPattern
                        }

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (!event.isAutoRepeat && win.keysArmed)
                                    win.answer();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                win.secondary();
                                event.accepted = true;
                            }
                        }
                    }
                }

                Chip {
                    id: revealChip
                    visible: win.secret
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.revealed ? "Hide" : "Show"
                    onClicked: win.revealed = !win.revealed
                }
            }

            Row {
                anchors.right: parent.right
                spacing: 8

                Chip {
                    text: win.secondaryText
                    onClicked: win.secondary()
                }

                Chip {
                    visible: win.primaryText !== ""
                    text: win.primaryText
                    selected: true
                    enabled: win.ready
                    onClicked: win.answer()
                }
            }
        }
    }
}
