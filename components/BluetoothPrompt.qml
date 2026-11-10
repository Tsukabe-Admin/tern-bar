import QtQuick
import "../singletons"

// The question BlueZ puts during a pairing (see BluetoothAgent): a PIN or a
// passkey to type, a number to compare, "may this device pair or connect?",
// or a code to type on the device itself. One window for the whole shell,
// under the bar on the screen that had focus when the question came; the
// window and its keyboard rules are PromptWindow's.
PromptWindow {
    id: win

    readonly property var prompt: BluetoothAgent.prompt
    readonly property string kind: win.prompt ? win.prompt.kind : ""
    readonly property bool yesNo: win.kind === "confirm" || win.kind === "authorize" || win.kind === "service"
    readonly property bool shown: win.kind === "show-pin" || win.kind === "show-passkey"

    token: win.prompt
    open: win.prompt !== null
    screenName: win.prompt ? win.prompt.screenName : ""
    glyph: "\uf294"
    title: BluetoothAgent.nameOf(win.prompt)
    typed: win.kind === "pin" || win.kind === "passkey"
    maxLength: win.kind === "passkey" ? 6 : 16
    inputPattern: win.kind === "passkey" ? /[0-9]{0,6}/ : /[0-9A-Za-z]{0,16}/
    accept: (text) => win.kind === "pin" ? /^[0-9A-Za-z]{1,16}$/.test(text)
        : win.kind === "passkey" ? /^[0-9]{1,6}$/.test(text) : true
    layerNamespace: "tern-bar-bluetooth"

    message: {
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
    // The number to compare, or the code to type on the device, and how much
    // of it has been typed there so far.
    code: win.prompt ? win.spaced(win.prompt.code) : ""
    codeNote: (win.kind === "show-passkey" && win.prompt.entered > 0) ? win.prompt.entered + " of 6 typed" : ""
    primaryText: (win.typed || win.kind === "confirm") ? "Pair" : win.yesNo ? "Allow" : ""
    secondaryText: (win.kind === "authorize" || win.kind === "service") ? "Refuse"
        : win.shown ? "Stop pairing" : "Cancel"

    onPrimary: (text) => {
        if (win.typed)
            BluetoothAgent.answer(win.kind === "passkey" ? Number(text) : text);
        else if (win.yesNo)
            BluetoothAgent.answer(true);
    }
    onSecondary: BluetoothAgent.dismiss()

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
}
