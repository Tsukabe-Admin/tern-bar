import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import "../singletons"

// Quick settings: Wi-Fi, Bluetooth, Do Not Disturb and night light tiles, the
// power profile, paired Bluetooth devices (click to connect/disconnect) and
// links to the full settings apps. Shown while Popups.open is "quick" on this
// bar's screen. A tile whose service is missing is hidden; night light without
// wlsunset says what to install.
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

    readonly property point anchorPos: (pop.visible && pop.anchorItem)
        ? pop.anchorItem.mapToItem(null, 0, 0) : Qt.point(0, 0)

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var wifiDevice: {
        const list = Networking.devices.values;
        for (let i = 0; i < list.length; i++) {
            if (list[i].type === DeviceType.Wifi)
                return list[i];
        }
        return null;
    }
    readonly property string wifiName: {
        if (!pop.wifiDevice)
            return "";
        const list = pop.wifiDevice.networks.values;
        for (let i = 0; i < list.length; i++) {
            if (list[i].connected)
                return list[i].name;
        }
        return "";
    }
    // Paired devices, connected first, then by name; at most six.
    readonly property var btDevices: {
        if (!pop.adapter)
            return [];
        const list = pop.adapter.devices.values.filter((d) => d.paired);
        list.sort((a, b) => (Number(b.connected) - Number(a.connected))
            || (a.deviceName || a.name).localeCompare(b.deviceName || b.name));
        return list.slice(0, 6);
    }
    readonly property int btConnected: pop.btDevices.filter((d) => d.connected).length

    MouseArea {
        anchors.fill: parent
        enabled: pop.visible
        onClicked: Popups.close()
    }

    Rectangle {
        id: card
        width: 340
        height: col.implicitHeight + 24
        x: Math.max(0, Math.min(pop.anchorPos.x + (pop.anchorItem ? pop.anchorItem.width : 0) - card.width,
            pop.width - card.width))
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
                    visible: pop.wifiDevice !== null
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
                        : pop.btConnected > 0 ? pop.btConnected + " connected" : "On"
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
                    subtitle: !NightLight.available ? "Install wlsunset" : NightLight.on ? "4000 K" : "Off"
                    on: NightLight.on
                    onClicked: NightLight.toggle()
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

            Column {
                visible: !!(pop.adapter && pop.adapter.enabled) && pop.btDevices.length > 0
                width: parent.width
                spacing: 2

                Text {
                    textFormat: Text.PlainText
                    text: "Bluetooth devices"
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Repeater {
                    model: pop.btDevices

                    Item {
                        id: devRow
                        required property var modelData

                        width: parent.width
                        height: 32

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.itemRadius
                            color: devHover.hovered ? Theme.hover : "transparent"
                        }

                        Text {
                            textFormat: Text.PlainText
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: devState.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: devRow.modelData.deviceName || devRow.modelData.name
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: Theme.t1
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        Text {
                            textFormat: Text.PlainText
                            id: devState
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: (devRow.modelData.batteryAvailable
                                    ? Math.round(devRow.modelData.battery * 100) + "%  " : "")
                                + (devRow.modelData.connected ? "Connected"
                                    : devRow.modelData.state === BluetoothDeviceState.Connecting ? "Connecting…" : "")
                            color: devRow.modelData.connected ? Theme.accent : Theme.t3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        HoverHandler {
                            id: devHover
                        }

                        TapHandler {
                            onTapped: {
                                if (devRow.modelData.connected)
                                    devRow.modelData.disconnect();
                                else
                                    devRow.modelData.connect();
                            }
                        }
                    }
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
