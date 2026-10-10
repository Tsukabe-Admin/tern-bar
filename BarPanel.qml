import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "singletons"

// The bar is a row of capsules ("pills"), one per group of items, floating on
// a transparent surface. Geometry matches waybar's occupancy exactly: 8px from
// the top, 12px sides, 40px tall, 48px reserved.
PanelWindow {
    id: bar

    required property var modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: Theme.barMarginTop
        left: Theme.barMarginSide
        right: Theme.barMarginSide
    }
    exclusiveZone: Theme.exclusiveZone
    implicitHeight: Theme.barHeight
    color: "transparent"

    BackgroundEffect.blurRegion: Region {
        Region { item: launcherPill }
        Region { item: workspacesPill }
        Region { item: titlePill }
        Region { item: ternPill }
        Region { item: clockPill }
        Region { item: mediaPill }
        Region { item: resourcesPill }
        Region { item: networkPill }
        Region { item: volumePill }
        Region { item: trayPill }
        Region { item: toolsPill }
        Region { item: systemPill }
    }

    Row {
        id: leftRow
        anchors.left: parent.left
        anchors.leftMargin: Theme.barPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.pillSpacing

        Pill {
            id: launcherPill
            IconButton {
                text: "󰣇"
                fg: Theme.accent
                action: () => Quickshell.execDetached(["fuzzel"])
                rightAction: () => Quickshell.execDetached(["/home/tsu/.config/niri/scripts/cheatsheet.sh"])
            }
        }

        Pill {
            id: workspacesPill
            Workspaces {
                output: bar.modelData.name
            }
        }

        Pill {
            id: titlePill
            visible: titleItem.hasWindow
            WindowTitle {
                id: titleItem
                output: bar.modelData.name
            }
        }
    }

    Row {
        id: centerRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.pillSpacing

        Pill {
            id: clockPill
            Clock {}
        }

        Pill {
            id: mediaPill
            visible: mediaItem.hasPlayer
            MprisPill {
                id: mediaItem
            }
        }
    }

    Row {
        id: rightRow
        anchors.right: parent.right
        anchors.rightMargin: Theme.barPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.pillSpacing

        Pill {
            id: resourcesPill
            Resources {}
        }

        Pill {
            id: networkPill
            Network {}
        }

        Pill {
            id: volumePill
            Volume {}
        }

        Pill {
            id: trayPill
            visible: SystemTray.items.values.length > 0
            Tray {
                barWindow: bar
                screenInfo: bar.modelData
            }
        }

        Pill {
            id: toolsPill
            IconButton {
                text: "󰸉"
                fg: Theme.t2
                action: () => Quickshell.execDetached(["waypaper"])
            }
            IconButton {
                text: "󰋖"
                fg: Theme.t3
                action: () => Quickshell.execDetached(["/home/tsu/.config/niri/scripts/cheatsheet.sh"])
            }
        }

        Pill {
            id: systemPill
            Bell {}
            IconButton {
                text: "⏻"
                fg: Theme.bad
                action: () => Quickshell.execDetached(["/home/tsu/.config/niri/scripts/powermenu.sh"])
            }
        }
    }

    // The Tern pill lives in whichever group BarConfig.ternPillSide names; it
    // is reparented at runtime (right-click cycles it, bar.json persists it).
    Pill {
        id: ternPill
        TernPill {
            launch: () => {
                // Open on the screen whose pill was clicked: niri puts new
                // windows on the focused output, and hovering the bar does not
                // change that.
                Niri.focusMonitor(bar.modelData.name);
                if (morphLoader.item)
                    morphLoader.item.launchFrom(ternPill);
                else
                    Tern.open();
            }
            cycleSide: () => BarConfig.cycleTernPillSide()
        }
    }

    function placeTernPill() {
        const target = BarConfig.ternPillSide === "left" ? leftRow
            : BarConfig.ternPillSide === "center" ? centerRow
            : rightRow;
        if (ternPill.parent !== target)
            ternPill.parent = target;
    }

    Component.onCompleted: placeTernPill()

    Connections {
        target: BarConfig
        function onTernPillSideChanged() {
            bar.placeTernPill();
        }
    }

    // The morph overlay exists only while it is explicitly enabled, so the
    // bar normally never creates a second, fullscreen layer surface.
    Loader {
        id: morphLoader
        active: BarConfig.morphEnabled
        sourceComponent: Component {
            TernMorph {
                screenInfo: bar.modelData
                screenName: bar.modelData.name
            }
        }
    }
}
