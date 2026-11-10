pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// tern-bar's Bluetooth pairing agent. A pairing can need a person: a PIN or a
// passkey to type, a number to compare with the one on the device, "may this
// device pair or connect?". BlueZ puts those questions to a pairing agent, and
// Quickshell has none, so the bar runs tools/bt-agent (installed as
// tern-bar-bt-agent). It registers with BlueZ as the default agent and passes
// each question here as one line of JSON (the format is described at the top of
// tools/bt-agent/src/main.rs). BluetoothPrompt shows it, and the answer goes
// back the same way.
//
// Without the program, only devices that pair without a code can be paired
// from the bar: BlueZ then has nobody to ask.
Singleton {
    id: root

    readonly property string program: "tern-bar-bt-agent"
    readonly property bool installed: Programs.has(root.program)
    // Registered with BlueZ: its questions come to the bar.
    property bool active: false
    // The question on screen, or null:
    //   { id, kind, device, address, code, entered, uuid, screenName }
    // kind "pin" or "passkey": type an answer. "confirm", "authorize" or
    // "service": yes or no. "show-pin" or "show-passkey": type this code on the
    // device itself; nothing to answer, and no id.
    property var prompt: null
    // Starts of the helper that have failed since it last ran for a minute.
    property int failures: 0

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
        root.send(reply);
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
            root.send({ id: p.id });
        const device = root.deviceFor(p);
        if (device)
            BluetoothDevices.cancelPair(device);
    }

    function send(reply) {
        if (helper.running)
            helper.write(JSON.stringify(reply) + "\n");
    }

    function handle(line) {
        let message = null;
        try {
            message = JSON.parse(line);
        } catch (e) {
            console.warn("tern-bar-bt-agent wrote a line that is not JSON:", line);
            return;
        }
        if (message.event === "ready") {
            root.active = true;
            healthy.restart();
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
            console.warn("tern-bar-bt-agent:", message.message);
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

    // ── The helper ─────────────────────────────────────────────────────────
    // A helper that stops is started again after 5 s, then 30 s, then every
    // 5 minutes: never in a loop. A minute of normal running resets that.

    function start() {
        if (!root.installed || helper.running)
            return;
        helper.running = true;
        startCheck.restart();
    }

    function retry() {
        const delays = [5000, 30000, 300000];
        restartTimer.interval = delays[Math.min(root.failures, delays.length - 1)];
        root.failures++;
        restartTimer.restart();
    }

    Timer {
        id: restartTimer
        onTriggered: root.start()
    }

    // A program that cannot start at all sends no signal; this notices.
    Timer {
        id: startCheck
        interval: 3000
        onTriggered: {
            if (!helper.running && !restartTimer.running)
                root.retry();
        }
    }

    Timer {
        id: healthy
        interval: 60000
        onTriggered: root.failures = 0
    }

    Process {
        id: helper
        command: [root.program]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: (line) => root.handle(line)
        }
        // Only a crash writes here.
        stderr: SplitParser {
            onRead: (line) => console.warn("tern-bar-bt-agent:", line)
        }
        onRunningChanged: {
            if (helper.running)
                return;
            root.active = false;
            root.prompt = null;
            healthy.stop();
            root.retry();
        }
    }

    onInstalledChanged: root.start()
    Component.onCompleted: root.start()
}
