pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Skua's Bluetooth pairing agent. A pairing can need a person: a PIN or a
// passkey to type, a number to compare with the one on the device, "may this
// device pair or connect?". BlueZ puts those questions to a pairing agent, and
// Quickshell has none, so the bar runs `skua-helper bluetooth` (tools/skua-helper;
// the lines it writes are described at the top of src/bluetooth.rs). It
// registers with BlueZ as the default agent and passes each question here as one
// line of JSON. BluetoothPrompt shows it, and the answer goes back the same way.
//
// Without skua-helper, only devices that pair without a code can be paired from
// the bar: BlueZ then has nobody to ask.
Singleton {
    id: root

    readonly property bool installed: helper.installed
    // The helper was built from older sources than this copy of the bar.
    readonly property bool outdated: helper.outdated
    // Registered with BlueZ: its questions come to the bar.
    property bool active: false
    // The question on screen, or null:
    //   { id, kind, device, address, code, entered, uuid, screenName }
    // kind "pin" or "passkey": type an answer. "confirm", "authorize" or
    // "service": yes or no. "show-pin" or "show-passkey": type this code on the
    // device itself; nothing to answer, and no id.
    property var prompt: null

    function deviceFor(p) {
        if (!p)
            return null;
        const list = Bluetooth.devices.values;
        for (let i = 0; i < list.length; i++) {
            if (list[i].dbusPath === p.device)
                return list[i];
        }
        return null;
    }

    function nameOf(p) {
        const device = root.deviceFor(p);
        return device ? BluetoothDevices.label(device) : (p ? p.address : "");
    }

    // Answers the question on screen: the PIN or passkey typed, or true for yes.
    function answer(value) {
        const p = root.prompt;
        if (!p || p.id === undefined)
            return;
        const reply = { id: p.id };
        if (p.kind === "pin")
            reply.pin = String(value);
        else if (p.kind === "passkey")
            reply.passkey = Number(value);
        else
            reply.accept = value === true;
        root.prompt = null;
        helper.send(reply);
    }

    // Closes the prompt without a yes. A question is refused (an answer without
    // a value), a code on screen is withdrawn, and a pairing the card started
    // ends too, so its row goes back to "Pair" rather than "Couldn't pair".
    function dismiss() {
        const p = root.prompt;
        if (!p)
            return;
        root.prompt = null;
        if (p.id !== undefined)
            helper.send({ id: p.id });
        const device = root.deviceFor(p);
        if (device)
            BluetoothDevices.cancelPair(device);
    }

    function handle(message) {
        if (message.event === "ready") {
            root.active = true;
        } else if (message.event === "waiting") {
            root.active = false;
            root.prompt = null;
        } else if (message.event === "request") {
            root.open(message, message.kind);
        } else if (message.event === "show") {
            root.open(message, "show-" + message.kind);
        } else if (message.event === "cancel") {
            root.prompt = null;
        } else if (message.event === "error") {
            console.warn("skua-helper bluetooth:", message.message);
        }
    }

    // BlueZ asks one question at a time, so a new one replaces whatever is on
    // screen. A code shown again (a key was typed on the device) stays on the
    // screen it is on.
    function open(message, kind) {
        const old = root.prompt;
        const same = old !== null && old.device === message.device && old.kind === kind;
        root.prompt = {
            id: message.id,
            kind: kind,
            device: String(message.device || ""),
            address: String(message.address || ""),
            code: String(message.code || ""),
            entered: typeof message.entered === "number" ? message.entered : -1,
            uuid: String(message.uuid || ""),
            screenName: same ? old.screenName : Popups.focusedScreenName()
        };
    }

    // A code on screen closes when its device has paired or the card's pairing
    // has failed, also when BlueZ does not say so.
    Timer {
        interval: 500
        repeat: true
        running: root.prompt !== null && root.prompt.kind.indexOf("show-") === 0
        onTriggered: {
            const device = root.deviceFor(root.prompt);
            if (device && (device.paired || BluetoothDevices.stateOf(device) === "failed"))
                root.prompt = null;
        }
    }

    HelperJob {
        id: helper
        name: "bluetooth"
        onReceived: (message) => root.handle(message)
        onStopped: {
            root.active = false;
            root.prompt = null;
        }
    }
}
