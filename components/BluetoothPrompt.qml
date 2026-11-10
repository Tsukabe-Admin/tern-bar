import QtQuick
import Quickshell
import Quickshell.Wayland
import "../singletons"

// The question BlueZ puts during a pairing (see BluetoothAgent): a PIN or a
// passkey to type, a number to compare, "may this device pair or connect?",
// or a code to type on the device itself. One window for the whole shell,
// under the bar on the screen that had focus when the question came.
//
// Only a question that needs typing takes the keyboard, and its Enter counts
// only once the question has been up for half a second and the key is not a
// held key repeating. Yes/no questions are answered with the mouse: a key
// meant for something else must never let a device in.
PanelWindow {
    id: win

    readonly property var prompt: BluetoothAgent.prompt
    readonly property string kind: win.prompt ? win.prompt.kind : ""
    readonly property bool typed: win.kind === "pin" || win.kind === "passkey"
    readonly property bool yesNo: win.kind === "confirm" || win.kind === "authorize" || win.kind === "service"
    readonly property bool shown: win.kind === "show-pin" || win.kind === "show-passkey"
    readonly property string name: BluetoothAgent.nameOf(win.prompt)
    readonly property bool ready: win.kind === "pin" ? /^[0-9A-Za-z]{1,16}$/.test(field.text)
        : win.kind === "passkey" ? /^[0-9]{1,6}$/.test(field.text) : true
    property bool keysArmed: false

    readonly property string message: {
        if (win.kind === "pin")
            return "Type the PIN for this device. If its manual gives none, try 0000.";
        if (win.kind === "passkey")
            return "Type the 6-digit number the device shows.";
        if (win.kind === "confirm")
            return "Pair only if the device shows this number:";
        if (win.kind === "authorize")
            return "It asks to pair with this computer.";
        if (win.kind === "service")
            return "It asks to connect for " + win.serviceName(win.prompt.uuid) + ".";
        if (win.shown)
            return "Type this " + (win.kind === "show-pin" ? "PIN" : "number") + " on the device, then press Enter on it:";
        return "";
    }
    readonly property string primaryText: (win.typed || win.kind === "confirm") ? "Pair" : win.yesNo ? "Allow" : ""
    readonly property string secondaryText: (win.kind === "authorize" || win.kind === "service") ? "Refuse"
        : win.shown ? "Stop pairing" : "Cancel"

    screen: Popups.screenNamed(win.prompt ? win.prompt.screenName : "")
    visible: win.prompt !== null
    anchors.top: true
    margins.top: Theme.barMarginTop + Theme.barHeight + 12
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: card.width
    implicitHeight: card.height
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "tern-bar-bluetooth"
    WlrLayershell.keyboardFocus: win.typed ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // A new question: the field starts empty and Enter waits half a second.
    // The kind is read from the question itself: `typed` is a binding on the
    // same change and may not have caught up yet when this runs.
    onPromptChanged: {
        win.keysArmed = false;
        const kind = win.prompt ? win.prompt.kind : "";
        if (kind !== "pin" && kind !== "passkey")
            return;
        field.text = "";
        armTimer.restart();
        Qt.callLater(() => field.forceActiveFocus());
    }

    function primary() {
        if (win.typed && win.ready)
            BluetoothAgent.answer(win.kind === "passkey" ? Number(field.text) : field.text);
        else if (win.yesNo)
            BluetoothAgent.answer(true);
    }

    function secondary() {
        BluetoothAgent.dismiss();
    }

    // "123456" reads as "123 456".
    function spaced(code) {
        return /^[0-9]{6}$/.test(code) ? code.slice(0, 3) + " " + code.slice(3) : code;
    }

    // What a device asks to use, from the short form of a standard service UUID.
    function serviceName(uuid) {
        const names = {
            "110a": "audio", "110b": "audio", "110c": "media controls", "110e": "media controls",
            "1108": "a headset", "1112": "a headset", "111e": "hands-free calls", "111f": "hands-free calls",
            "1124": "keyboard or mouse input", "1105": "file transfer", "1106": "file transfer",
            "1115": "networking", "1116": "networking", "112f": "the phone book", "1132": "messages"
        };
        return names[String(uuid).toLowerCase().slice(4, 8)] || "a Bluetooth service";
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
                    text: "\uf294"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 2
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width - 30
                    text: win.name
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

            // The number to compare, or the code to type on the device.
            Text {
                textFormat: Text.PlainText
                visible: win.prompt !== null && win.prompt.code !== ""
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: win.prompt ? win.spaced(win.prompt.code) : ""
                color: Theme.t1
                font.family: Theme.fontFamily
                font.pixelSize: 28
                font.bold: true
                font.letterSpacing: 2
            }

            // How much of the code has been typed on the device so far.
            Text {
                textFormat: Text.PlainText
                visible: win.kind === "show-passkey" && win.prompt.entered > 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: win.prompt ? win.prompt.entered + " of 6 typed" : ""
                color: Theme.t3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }

            Rectangle {
                visible: win.typed
                width: parent.width
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
                    color: Theme.t1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    maximumLength: win.kind === "passkey" ? 6 : 16
                    validator: RegularExpressionValidator {
                        regularExpression: win.kind === "passkey" ? /[0-9]{0,6}/ : /[0-9A-Za-z]{0,16}/
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (!event.isAutoRepeat && win.keysArmed)
                                win.primary();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            win.secondary();
                            event.accepted = true;
                        }
                    }
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
                    onClicked: win.primary()
                }
            }
        }
    }
}
