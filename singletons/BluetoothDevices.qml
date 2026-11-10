pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth

// The Bluetooth devices the quick-settings card lists, and what can be done
// with them there: search for new ones, pair, connect, forget.
//
// Devices that pair without a code ("just works": headphones, speakers, mice,
// game controllers) need nothing more. A pairing that needs a person (a PIN,
// a passkey, "does the device show this number?") is asked of BlueZ's pairing
// agent: tern-bar's helper when it is installed (BluetoothAgent shows the
// question). Without it such a pairing fails, and the card says so.
Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: !!(root.adapter && root.adapter.enabled)

    function label(device) {
        return device.deviceName || device.name || device.address;
    }

    // Paired devices, connected first, then by name; at most six.
    readonly property var paired: {
        if (!root.adapter)
            return [];
        const list = root.adapter.devices.values.filter((d) => d.paired);
        list.sort((a, b) => (Number(b.connected) - Number(a.connected))
            || root.label(a).localeCompare(root.label(b)));
        return list.slice(0, 6);
    }
    readonly property int connectedCount: root.paired.filter((d) => d.connected).length

    // ── Searching ──────────────────────────────────────────────────────────
    // On from "Find devices" until "Stop", the card closing, Bluetooth being
    // switched off, or a minute passing: a search slows the radio down, and
    // Bluetooth audio can stutter while one runs. BlueZ also ends it when the
    // bar quits.
    property bool searching: false

    function search(on) {
        if (!root.adapter || (on && !root.enabled))
            return;
        if (on) {
            root.attempts = root.only("pairing");
            root.nearbyExpanded = false;
        }
        root.searching = on;
        root.adapter.discovering = on;
        if (on)
            searchTimer.restart();
        else
            searchTimer.stop();
    }

    // ── Pairing ────────────────────────────────────────────────────────────
    // address → { state: "pairing" | "failed", since: ms }. Kept here, not in
    // the card, so a pairing still finishes (trusted, connected) when the card
    // is closed halfway.
    property var attempts: ({})
    readonly property bool busy: Object.keys(root.only("pairing")).length > 0
    readonly property bool anyFailed: Object.keys(root.only("failed")).length > 0
    // The adapter accepts pairing while one of ours runs, and goes back to how
    // it was set afterwards. With it off, a mouse or a controller pairs without
    // its keys being kept, and has to be paired again after every disconnect.
    property bool madePairable: false

    function only(state) {
        const out = {};
        for (const address in root.attempts) {
            if (root.attempts[address].state === state)
                out[address] = root.attempts[address];
        }
        return out;
    }

    function setAttempt(address, state) {
        const next = Object.assign({}, root.attempts);
        if (state === "")
            delete next[address];
        else
            next[address] = { state: state, since: Date.now() };
        root.attempts = next;
    }

    function stateOf(device) {
        const attempt = root.attempts[device.address];
        return attempt ? attempt.state : "";
    }

    function pair(device) {
        if (!root.enabled || device.paired || device.pairing)
            return;
        if (!root.adapter.pairable) {
            root.madePairable = true;
            root.adapter.pairable = true;
        }
        root.setAttempt(device.address, "pairing");
        device.pair();
        pairWatch.start();
    }

    function cancelPair(device) {
        root.setAttempt(device.address, "");
        if (device.pairing)
            device.cancelPair();
    }

    function toggleConnection(device) {
        if (device.connected)
            device.disconnect();
        else if (device.state !== BluetoothDeviceState.Connecting)
            device.connect();
    }

    function forget(device) {
        device.forget();
    }

    // Devices a search has found that are not paired yet and have a name.
    // The ones being paired come first, then the ones that say what they are
    // (headphones, mouse, phone: what people pair), then the rest, each by
    // name. Nameless ones are mostly beacons nobody could tell apart. A
    // pairing started before the card closed keeps its row. In a busy street
    // the list is long, so the card shows the first few and a "Show more" row
    // (nearbyExpanded).
    readonly property bool showNearby: root.enabled && (root.searching || root.busy)
    property bool nearbyExpanded: false
    readonly property var nearby: {
        if (!root.showNearby)
            return [];
        const asked = root.attempts;
        const list = root.adapter.devices.values.filter((d) => !d.paired
            && (asked[d.address] !== undefined || (root.searching && d.deviceName !== "")));
        list.sort((a, b) => (Number(asked[b.address] !== undefined) - Number(asked[a.address] !== undefined))
            || (Number(b.icon !== "") - Number(a.icon !== ""))
            || root.label(a).localeCompare(root.label(b)));
        return list;
    }

    function deviceAt(address) {
        if (!root.adapter)
            return null;
        const list = root.adapter.devices.values;
        for (let i = 0; i < list.length; i++) {
            if (list[i].address === address)
                return list[i];
        }
        return null;
    }

    // Quickshell's pair() reports nothing back: `pairing` is true while BlueZ
    // works on it, and `paired` turns true if it worked. A failure is
    // `pairing` back to false with `paired` still false; the second and a
    // half lets a late "paired" arrive first.
    Timer {
        id: pairWatch
        interval: 500
        repeat: true
        onTriggered: {
            const pending = root.only("pairing");
            for (const address in pending) {
                const device = root.deviceAt(address);
                if (device && device.paired) {
                    root.setAttempt(address, "");
                    device.trusted = true;     // it may reconnect by itself from now on
                    if (!device.connected && device.state !== BluetoothDeviceState.Connecting)
                        device.connect();
                } else if (!device || (!device.pairing && Date.now() - pending[address].since > 1500)) {
                    root.setAttempt(address, "failed");
                }
            }
            if (!root.busy) {
                pairWatch.stop();
                if (root.madePairable && root.adapter)
                    root.adapter.pairable = false;
                root.madePairable = false;
            }
        }
    }

    Timer {
        id: searchTimer
        interval: 60000
        onTriggered: root.search(false)
    }

    Connections {
        target: Popups

        function onOpenChanged() {
            if (Popups.open !== "quick" && root.searching)
                root.search(false);
        }
    }

    onEnabledChanged: {
        if (!root.enabled) {
            root.searching = false;
            searchTimer.stop();
        }
    }
}
