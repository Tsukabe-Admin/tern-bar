import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import "../singletons"

// Quick settings: Wi-Fi, Bluetooth, Do Not Disturb, night light, keep awake and
// microphone tiles, screen brightness and microphone input volume sliders, the
// sound output and input devices (when there is more than one to choose
// from), the power profile, Wi-Fi networks (connect, with a password when one
// is needed; forget; see WifiNetworks), Bluetooth devices (find new ones,
// pair, connect/disconnect, forget; see BluetoothDevices) and links to the
// full settings apps. Shown while Popups.open is "quick" on this bar's screen.
// A tile or slider whose hardware/service is missing is hidden; night light
// without wlsunset says what to install.
PopupWindow {
    id: pop

    property var barWindow: null
    property var screenInfo: null
    property Item anchorItem: null

    visible: Popups.open === "quick" && pop.screenInfo !== null
        && Popups.screenName === pop.screenInfo.name
    anchor.window: pop.barWindow
    anchor.rect.x: 0
    anchor.rect.y: 0
    anchor.rect.width: 1
    anchor.rect.height: 1
    grabFocus: false
    color: "transparent"
    implicitWidth: (pop.screenInfo ? pop.screenInfo.width : 1000) - Theme.barMarginSide
    implicitHeight: (pop.screenInfo ? pop.screenInfo.height : 1000) - Theme.barMarginTop

    readonly property bool hasAnchor: pop.anchorItem !== null && pop.anchorItem.visible
    readonly property point anchorPos: (pop.visible && pop.hasAnchor)
        ? pop.anchorItem.mapToItem(null, 0, 0) : Qt.point(0, 0)

    readonly property var mic: Pipewire.defaultAudioSource
    readonly property bool hasMic: pop.mic !== null && pop.mic.audio !== null
    readonly property real micVol: pop.hasMic ? pop.mic.audio.volume : 0
    readonly property bool micMuted: pop.hasMic ? pop.mic.audio.muted : false

    PwObjectTracker {
        objects: pop.mic ? [pop.mic] : []
    }

    // Sound devices (not the apps' streams): where sound goes, and where it
    // comes from.
    readonly property var sinks: Pipewire.nodes.values.filter((n) =>
        (n.type & PwNodeType.AudioSink) === PwNodeType.AudioSink && !(n.type & PwNodeType.Stream))
    readonly property var sources: Pipewire.nodes.values.filter((n) =>
        (n.type & PwNodeType.AudioSource) === PwNodeType.AudioSource && !(n.type & PwNodeType.Stream))

    function nodeLabel(n) {
        return n.description || n.nickname || n.name;
    }

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property string wifiName: {
        const list = WifiNetworks.list;
        return (list.length > 0 && list[0].connected) ? list[0].name : "";
    }

    // A network's row label: its signal (with a lock when it needs a key), then its name.
    function wifiLabel(n) {
        const level = Math.min(3, Math.floor(n.signalStrength * 4));
        const glyphs = WifiNetworks.secured(n)
            ? ["󰤠", "󰤣", "󰤦", "󰤩"]
            : ["󰤟", "󰤢", "󰤥", "󰤨"];
        return glyphs[Math.max(0, level)] + "  " + n.name;
    }

    MouseArea {
        anchors.fill: parent
        enabled: pop.visible
        onClicked: Popups.close()
    }

    Rectangle {
        id: card
        width: 340
        height: col.implicitHeight + 24
        x: pop.hasAnchor
            ? Math.max(0, Math.min(pop.anchorPos.x + pop.anchorItem.width - card.width, pop.width - card.width))
            : Math.max(0, pop.width - card.width)
        y: Theme.barHeight + 4
        radius: Theme.radiusCard
        color: Theme.popBg
        border.width: 1
        border.color: Theme.rim

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: col
            x: 12
            y: 12
            width: card.width - 24
            spacing: 12

            Grid {
                columns: 2
                spacing: 8

                QsTile {
                    visible: WifiNetworks.device !== null
                    enabled: Networking.wifiHardwareEnabled
                    glyph: "\uf1eb"
                    title: "Wi-Fi"
                    subtitle: !Networking.wifiEnabled ? "Off" : (pop.wifiName || "Not connected")
                    on: Networking.wifiEnabled
                    onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                }

                QsTile {
                    visible: pop.adapter !== null
                    glyph: "\uf294"
                    title: "Bluetooth"
                    subtitle: !(pop.adapter && pop.adapter.enabled) ? "Off"
                        : BluetoothDevices.connectedCount > 0 ? BluetoothDevices.connectedCount + " connected" : "On"
                    on: !!(pop.adapter && pop.adapter.enabled)
                    onClicked: pop.adapter.enabled = !pop.adapter.enabled
                }

                QsTile {
                    enabled: Swaync.available
                    glyph: "\uf1f6"
                    title: "Do not disturb"
                    subtitle: !Swaync.available ? "Install swaync" : Swaync.dnd ? "On" : "Off"
                    on: Swaync.dnd
                    onClicked: Swaync.toggleDnd()
                }

                QsTile {
                    enabled: NightLight.available
                    glyph: "\uf186"
                    title: "Night light"
                    subtitle: !NightLight.available ? "Install wlsunset"
                        : NightLight.active ? "4000 K" : NightLight.problem !== "" ? NightLight.problem : "Off"
                    on: NightLight.active
                    onClicked: NightLight.toggle()
                }

                QsTile {
                    glyph: "󰅶"
                    title: "Keep awake"
                    subtitle: KeepAwake.on ? "Screen stays on" : "Off"
                    on: KeepAwake.on
                    onClicked: KeepAwake.toggle()
                }

                QsTile {
                    visible: pop.hasMic
                    glyph: pop.micMuted ? "󰍭" : "󰍬"
                    title: "Microphone"
                    subtitle: pop.micMuted ? "Muted" : Math.round(pop.micVol * 100) + "%"
                    on: !pop.micMuted
                    onClicked: {
                        if (pop.hasMic)
                            pop.mic.audio.muted = !pop.mic.audio.muted;
                    }
                }
            }

            Column {
                visible: Brightness.available
                width: parent.width
                spacing: 4

                Row {
                    width: parent.width
                    spacing: 10

                    Text {
                        textFormat: Text.PlainText
                        id: brIcon
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        horizontalAlignment: Text.AlignHCenter
                        text: brSlider.shownValue < 0.34 ? "󰃞" : brSlider.shownValue < 0.67 ? "󰃟" : "󰃠"
                        color: Theme.t2
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 2
                    }

                    SettingsSlider {
                        id: brSlider
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - brIcon.width - brLabel.width - 20
                        from: 0.01
                        to: 1.0
                        stepSize: 0.01
                        value: Brightness.value
                        onCommitted: (val) => Brightness.set(val)
                    }

                    Text {
                        textFormat: Text.PlainText
                        id: brLabel
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(brSlider.shownValue * 100) + "%"
                        color: Theme.t2
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
            }

            Column {
                visible: pop.hasMic
                width: parent.width
                spacing: 4

                Row {
                    width: parent.width
                    spacing: 10

                    Text {
                        textFormat: Text.PlainText
                        id: micIcon
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        horizontalAlignment: Text.AlignHCenter
                        text: pop.micMuted ? "󰍭" : "󰍬"
                        color: pop.micMuted ? Theme.t3 : Theme.t2
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 2

                        TapHandler {
                            onTapped: {
                                if (pop.hasMic)
                                    pop.mic.audio.muted = !pop.mic.audio.muted;
                            }
                        }
                    }

                    SettingsSlider {
                        id: micSlider
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - micIcon.width - micLabel.width - 20
                        from: 0
                        to: 1.0
                        stepSize: 0.01
                        value: pop.micVol
                        onCommitted: (val) => {
                            if (pop.hasMic)
                                pop.mic.audio.volume = val;
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        id: micLabel
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        horizontalAlignment: Text.AlignRight
                        text: pop.micMuted ? "Mute" : Math.round(micSlider.shownValue * 100) + "%"
                        color: pop.micMuted ? Theme.t3 : Theme.t2
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
            }

            // A click makes the device the one in use: Pipewire moves the
            // sound there, and the volume pill and sliders follow it.
            Column {
                visible: pop.sinks.length > 1 || pop.sources.length > 1
                width: parent.width
                spacing: 2

                Text {
                    textFormat: Text.PlainText
                    visible: pop.sinks.length > 1
                    bottomPadding: 4
                    text: "Output"
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Repeater {
                    model: pop.sinks.length > 1 ? pop.sinks : []

                    DeviceRow {
                        id: sinkRow
                        required property var modelData

                        label: pop.nodeLabel(sinkRow.modelData)
                        status: sinkRow.modelData === Pipewire.defaultAudioSink ? "In use" : ""
                        statusColor: Theme.accent
                        onTapped: Pipewire.preferredDefaultAudioSink = sinkRow.modelData
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    visible: pop.sources.length > 1
                    topPadding: pop.sinks.length > 1 ? 8 : 0
                    bottomPadding: 4
                    text: "Input"
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Repeater {
                    model: pop.sources.length > 1 ? pop.sources : []

                    DeviceRow {
                        id: sourceRow
                        required property var modelData

                        label: pop.nodeLabel(sourceRow.modelData)
                        status: sourceRow.modelData === Pipewire.defaultAudioSource ? "In use" : ""
                        statusColor: Theme.accent
                        onTapped: Pipewire.preferredDefaultAudioSource = sourceRow.modelData
                    }
                }
            }

            Column {
                visible: Programs.has("power-profiles")
                width: parent.width
                spacing: 6

                Text {
                    textFormat: Text.PlainText
                    text: "Power profile"
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Row {
                    spacing: 6

                    Chip {
                        text: "Saver"
                        selected: PowerProfiles.profile === PowerProfile.PowerSaver
                        onClicked: PowerProfiles.profile = PowerProfile.PowerSaver
                    }

                    Chip {
                        text: "Balanced"
                        selected: PowerProfiles.profile === PowerProfile.Balanced
                        onClicked: PowerProfiles.profile = PowerProfile.Balanced
                    }

                    Chip {
                        visible: PowerProfiles.hasPerformanceProfile
                        text: "Performance"
                        selected: PowerProfiles.profile === PowerProfile.Performance
                        onClicked: PowerProfiles.profile = PowerProfile.Performance
                    }
                }
            }

            // A click connects (asking for the password when one is needed),
            // or disconnects the connected network. Forget, on a known network,
            // asks for a second click within three seconds.
            Column {
                visible: WifiNetworks.enabled
                width: parent.width
                spacing: 2

                Text {
                    textFormat: Text.PlainText
                    bottomPadding: 4
                    text: "Wi-Fi networks"
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Text {
                    textFormat: Text.PlainText
                    visible: WifiNetworks.list.length === 0
                    width: parent.width
                    height: 32
                    leftPadding: 8
                    verticalAlignment: Text.AlignVCenter
                    text: "Looking for networks…"
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }

                Repeater {
                    model: WifiNetworks.expanded ? WifiNetworks.list : WifiNetworks.list.slice(0, 6)

                    DeviceRow {
                        id: wifiRow
                        required property var modelData
                        property bool confirming: false
                        readonly property string failure: WifiNetworks.failures[wifiRow.modelData.name] || ""

                        label: pop.wifiLabel(wifiRow.modelData)
                        status: wifiRow.modelData.connected ? "Connected"
                            : wifiRow.modelData.stateChanging ? "Connecting…"
                            : wifiRow.failure !== "" ? wifiRow.failure
                            : !WifiNetworks.supported(wifiRow.modelData) ? "Needs settings" : ""
                        statusColor: wifiRow.modelData.connected ? Theme.accent
                            : (wifiRow.failure !== "" && !wifiRow.modelData.stateChanging) ? Theme.bad : Theme.t3
                        actionText: !wifiRow.modelData.known ? "" : wifiRow.confirming ? "Forget?" : "Forget"
                        actionArmed: wifiRow.confirming
                        onTapped: WifiNetworks.activate(wifiRow.modelData, pop.screenInfo ? pop.screenInfo.name : "")
                        onActionClicked: {
                            if (wifiRow.confirming) {
                                wifiRow.confirming = false;
                                WifiNetworks.forget(wifiRow.modelData);
                            } else {
                                wifiRow.confirming = true;
                                wifiConfirmTimer.restart();
                            }
                        }

                        Timer {
                            id: wifiConfirmTimer
                            interval: 3000
                            onTriggered: wifiRow.confirming = false
                        }
                    }
                }

                DeviceRow {
                    visible: !WifiNetworks.expanded && WifiNetworks.list.length > 6
                    label: "Show " + (WifiNetworks.list.length - 6) + " more"
                    labelColor: Theme.t2
                    onTapped: WifiNetworks.expanded = true
                }
            }

            Column {
                visible: BluetoothDevices.enabled
                width: parent.width
                spacing: 2

                Item {
                    width: parent.width
                    height: findChip.height

                    Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Bluetooth devices"
                        color: Theme.t3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }

                    Chip {
                        id: findChip
                        anchors.right: parent.right
                        text: BluetoothDevices.searching ? "Stop" : "Find devices"
                        selected: BluetoothDevices.searching
                        onClicked: BluetoothDevices.search(!BluetoothDevices.searching)
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    visible: BluetoothDevices.paired.length === 0
                    width: parent.width
                    height: 32
                    leftPadding: 8
                    verticalAlignment: Text.AlignVCenter
                    text: "No devices paired yet"
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }

                // Paired: a click connects or disconnects; Forget asks for a
                // second click within three seconds.
                Repeater {
                    model: BluetoothDevices.paired

                    DeviceRow {
                        id: pairedRow
                        required property var modelData
                        property bool confirming: false

                        label: BluetoothDevices.label(pairedRow.modelData)
                        status: (pairedRow.modelData.batteryAvailable
                                ? Math.round(pairedRow.modelData.battery * 100) + "%  " : "")
                            + (pairedRow.modelData.connected ? "Connected"
                                : pairedRow.modelData.state === BluetoothDeviceState.Connecting ? "Connecting…" : "")
                        statusColor: pairedRow.modelData.connected ? Theme.accent : Theme.t3
                        actionText: pairedRow.confirming ? "Forget?" : "Forget"
                        actionArmed: pairedRow.confirming
                        onTapped: BluetoothDevices.toggleConnection(pairedRow.modelData)
                        onActionClicked: {
                            if (pairedRow.confirming) {
                                pairedRow.confirming = false;
                                BluetoothDevices.forget(pairedRow.modelData);
                            } else {
                                pairedRow.confirming = true;
                                confirmTimer.restart();
                            }
                        }

                        Timer {
                            id: confirmTimer
                            interval: 3000
                            onTriggered: pairedRow.confirming = false
                        }
                    }
                }

                Item {
                    visible: BluetoothDevices.showNearby
                    width: parent.width
                    height: 28

                    Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        text: "Nearby"
                        color: Theme.t3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        visible: BluetoothDevices.searching
                        text: "Searching…"
                        color: Theme.t3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    visible: BluetoothDevices.showNearby && BluetoothDevices.nearby.length === 0
                    width: parent.width
                    leftPadding: 8
                    rightPadding: 8
                    wrapMode: Text.WordWrap
                    text: "Put the device in pairing mode and it will show up here."
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }

                // Not paired yet: a click pairs, then the device is trusted and
                // connected and moves up to the paired list. A click while it
                // pairs cancels.
                Repeater {
                    model: BluetoothDevices.nearbyExpanded ? BluetoothDevices.nearby : BluetoothDevices.nearby.slice(0, 6)

                    DeviceRow {
                        id: nearbyRow
                        required property var modelData
                        readonly property string attempt: BluetoothDevices.stateOf(nearbyRow.modelData)

                        label: BluetoothDevices.label(nearbyRow.modelData)
                        status: nearbyRow.attempt === "pairing" ? (nearbyRow.hovered ? "Cancel" : "Pairing…")
                            : nearbyRow.attempt === "failed" ? "Couldn't pair" : "Pair"
                        statusColor: nearbyRow.attempt === "failed" ? Theme.bad
                            : nearbyRow.attempt === "pairing" ? Theme.t3 : Theme.accent
                        onTapped: {
                            if (nearbyRow.attempt === "pairing")
                                BluetoothDevices.cancelPair(nearbyRow.modelData);
                            else
                                BluetoothDevices.pair(nearbyRow.modelData);
                        }
                    }
                }

                DeviceRow {
                    visible: !BluetoothDevices.nearbyExpanded && BluetoothDevices.nearby.length > 6
                    label: "Show " + (BluetoothDevices.nearby.length - 6) + " more"
                    labelColor: Theme.t2
                    onTapped: BluetoothDevices.nearbyExpanded = true
                }

                Text {
                    textFormat: Text.PlainText
                    visible: BluetoothDevices.showNearby && BluetoothDevices.anyFailed
                    width: parent.width
                    topPadding: 4
                    leftPadding: 8
                    rightPadding: 8
                    wrapMode: Text.WordWrap
                    text: BluetoothAgent.active
                        ? "Check that the device is still in pairing mode, then click it again."
                        : "Check that the device is still in pairing mode, then click it again. A device that asks for a PIN code needs tern-bar's pairing helper; the README says how to install it."
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            Row {
                spacing: 6

                Chip {
                    text: "Network settings"
                    onClicked: {
                        Popups.close();
                        Quickshell.execDetached(["nm-connection-editor"]);
                    }
                }

                Chip {
                    visible: Programs.has("blueman-manager")
                    text: "Bluetooth settings"
                    onClicked: {
                        Popups.close();
                        Quickshell.execDetached(["blueman-manager"]);
                    }
                }
            }
        }
    }
}
