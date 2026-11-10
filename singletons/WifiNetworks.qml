pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking

// Wi-Fi networks for the quick-settings card (NetworkManager, through
// Quickshell): the list, connecting, disconnecting and forgetting, and why the
// last connection to a network failed. A network that needs a password opens
// WifiPrompt; one that needs more than a password (enterprise logins, WEP)
// opens nm-connection-editor instead. The radio scans only while the card is
// open.
Singleton {
    id: root

    readonly property var device: {
        const list = Networking.devices.values;
        for (let i = 0; i < list.length; i++) {
            if (list[i].type === DeviceType.Wifi)
                return list[i];
        }
        return null;
    }
    readonly property bool enabled: root.device !== null && Networking.wifiEnabled

    // Named networks: the connected one first, then known ones, then by signal.
    readonly property var list: root.device
        ? root.device.networks.values.filter((n) => n.name !== "")
            .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
        : []

    // The card shows six networks until "Show N more" is clicked; closing the
    // card folds the list again.
    property bool expanded: false

    // The password question on screen: { network, screenName, retry }, or null.
    property var pending: null
    // Network name → why its last connection failed, for a few seconds.
    property var failures: ({})
    property string lastScreen: ""

    readonly property var pskTypes: [WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae]

    function needsPassword(n) {
        return !n.known && root.pskTypes.includes(n.security);
    }

    // What this card can connect to by itself: known networks, open ones, and
    // ones that need only a password.
    function supported(n) {
        return n.known || root.needsPassword(n) || n.security === WifiSecurityType.Open
            || n.security === WifiSecurityType.Owe;
    }

    function secured(n) {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
    }

    // A click on a network's row.
    function activate(n, screenName) {
        root.lastScreen = screenName;
        root.clearFailure(n.name);
        if (n.connected || n.stateChanging) {
            n.disconnect();
        } else if (!root.supported(n)) {
            Popups.close();
            Quickshell.execDetached(["nm-connection-editor"]);
        } else if (root.needsPassword(n)) {
            root.pending = { network: n, screenName: screenName, retry: false };
        } else {
            n.connect();
        }
    }

    function submit(psk) {
        const p = root.pending;
        root.pending = null;
        if (p && p.network)
            p.network.connectWithPsk(psk);
    }

    function cancel() {
        root.pending = null;
    }

    function forget(n) {
        root.clearFailure(n.name);
        n.forget();
    }

    function clearFailure(name) {
        if (!(name in root.failures))
            return;
        const next = Object.assign({}, root.failures);
        delete next[name];
        root.failures = next;
    }

    function failed(n, reason) {
        let text = "Couldn't connect";
        let askAgain = false;
        if (reason === ConnectionFailReason.NoSecrets) {
            text = "Wrong password";
            askAgain = root.pskTypes.includes(n.security);
        } else if (reason === ConnectionFailReason.WifiAuthTimeout) {
            text = "Timed out — check the password";
            askAgain = root.pskTypes.includes(n.security);
        } else if (reason === ConnectionFailReason.WifiNetworkLost) {
            text = "Out of range";
        }
        const next = Object.assign({}, root.failures);
        next[n.name] = text;
        root.failures = next;
        failureTimer.restart();
        if (askAgain)
            root.pending = {
                network: n,
                screenName: root.lastScreen !== "" ? root.lastScreen : Popups.focusedScreenName(),
                retry: true
            };
    }

    Timer {
        id: failureTimer
        interval: 8000
        onTriggered: root.failures = {}
    }

    Instantiator {
        model: root.device ? root.device.networks : null

        delegate: Connections {
            required property var modelData
            target: modelData

            function onConnectionFailed(reason) {
                root.failed(modelData, reason);
            }
        }
    }

    // Scanning costs power and can make Wi-Fi stutter: only while the card is open.
    Binding {
        when: root.device !== null
        target: root.device
        property: "scannerEnabled"
        value: Popups.open === "quick"
    }

    Connections {
        target: Popups

        function onOpenChanged() {
            if (Popups.open !== "quick")
                root.expanded = false;
        }
    }
}
