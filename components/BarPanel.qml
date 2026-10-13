import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "../singletons"

// The bar is a row of capsules ("pills"), one per group of items, floating on
// a transparent surface. Geometry matches waybar's occupancy exactly: 8px from
// the top, 12px sides, 40px tall, 48px reserved.
//
// Which pill sits in which of the three rows, and in what order, comes from
// BarConfig.layout; hidden pills stay alive in pillStore. Reparenting keeps the
// pill objects themselves, so their timers, sockets and scroll state survive a
// move — the rows hold no children of their own.
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

    // Only shown pills belong in the blur region — each PillRegion tracks its
    // pill's own box (see the component for why the geometry is explicit).
    BackgroundEffect.blurRegion: Region {
        PillRegion { pill: launcherPill; pillId: "launcher" }
        PillRegion { pill: workspacesPill; pillId: "workspaces" }
        PillRegion { pill: titlePill; pillId: "title" }
        PillRegion { pill: ternPill; pillId: "tern" }
        PillRegion { pill: pokePill; pillId: "poke" }
        PillRegion { pill: clockPill; pillId: "clock" }
        PillRegion { pill: mediaPill; pillId: "media" }
        PillRegion { pill: resourcesPill; pillId: "resources" }
        PillRegion { pill: networkPill; pillId: "network" }
        PillRegion { pill: volumePill; pillId: "volume" }
        PillRegion { pill: trayPill; pillId: "tray" }
        PillRegion { pill: toolsPill; pillId: "tools" }
        PillRegion { pill: systemPill; pillId: "system" }
    }

    Row {
        id: leftRow
        anchors.left: parent.left
        anchors.leftMargin: Theme.barPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.pillSpacing
    }

    Row {
        id: centerRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.pillSpacing
    }

    Row {
        id: rightRow
        anchors.right: parent.right
        anchors.rightMargin: Theme.barPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.pillSpacing
    }

    // Where every pill is declared, and where the hidden ones stay. Invisible,
    // so a pill parked here costs nothing on screen; assigning an Item's
    // `parent` appends it, which is what gives each row the layout's order.
    Item {
        id: pillStore
        visible: false

        Pill {
            id: launcherPill
            IconButton {
                text: "󰣇"
                fg: Theme.accent
                action: () => Quickshell.execDetached(["fuzzel"])
                rightAction: () => bar.openSettings("layout")
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

        // PokeToken: companion sprite + usage/limit parts (hidden until the
        // engine has written a status.json, so a missing plugin costs no space).
        Pill {
            id: pokePill
            visible: Poke.available
            PokePill {
                launch: () => {
                    Niri.focusMonitor(bar.modelData.name);
                    Poke.open("");
                }
                menuRequested: (item) => {
                    // Screen coordinates for the card: the bar window sits at the
                    // theme's margins, the item's own position is window-relative.
                    const p = item.mapToItem(null, 0, 0);
                    pokeMenu.barWindow = bar;
                    pokeMenu.screenInfo = bar.modelData;
                    pokeMenu.anchorX = Theme.barMarginSide + p.x;
                    pokeMenu.anchorY = Theme.barMarginTop + p.y + Theme.pillHeight + 4;
                    pokeMenu.openFor(item);
                }
            }
        }

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
                action: () => bar.openSettings("wallpaper")
            }
            IconButton {
                text: "󰋖"
                fg: Theme.t3
                action: () => Quickshell.execDetached([BarConfig.cheatsheetScript])
            }
            IconButton {
                text: "\uf013"
                fg: Theme.t2
                action: () => bar.openSettings("layout")
            }
        }

        Pill {
            id: systemPill
            Bell {}
            IconButton {
                text: "⏻"
                fg: Theme.bad
                action: () => Quickshell.execDetached([BarConfig.scriptsDir + "/power-menu.sh"])
            }
        }

        // Tern pill: right-click moves it to the next group (saved in bar.json).
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
    }

    readonly property var pills: ({
        launcher: launcherPill, workspaces: workspacesPill, title: titlePill, clock: clockPill,
        media: mediaPill, poke: pokePill, resources: resourcesPill, network: networkPill,
        volume: volumePill, tray: trayPill, tools: toolsPill, system: systemPill, tern: ternPill
    })

    function rowFor(side) {
        return side === "left" ? leftRow : side === "center" ? centerRow : rightRow;
    }

    // Place every pill from BarConfig.layout. Detaching everything first
    // matters: setting an Item's parent to the one it already has does nothing
    // in Qt, so a pill that only changed slot inside its row would never move.
    // The detach also drops each pill out of its blur Region (a parked pill is
    // not visible), which is what makes the region recompute once the pill is
    // placed again — a Region keeps the geometry it last saw.
    function applyLayout() {
        for (const id of BarConfig.pillIds) {
            const pill = bar.pills[id];
            if (pill)
                pill.parent = pillStore;
        }
        for (const side of BarConfig.sides) {
            const row = bar.rowFor(side);
            for (const id of BarConfig.layout[side] || []) {
                const pill = bar.pills[id];
                if (pill && !BarConfig.isHidden(id))
                    pill.parent = row;
            }
        }
    }

    // Open the settings page on the screen this bar is on (niri places a new
    // window on the focused output, and hovering the bar does not change that),
    // on `tab` — "layout" or "wallpaper".
    function openSettings(tab) {
        Niri.focusMonitor(bar.modelData.name);
        BarConfig.openSettings(tab);
    }

    Component.onCompleted: applyLayout()

    // Right-click menu for the PokeToken pill (a sibling window, like TrayMenu).
    PokeMenu {
        id: pokeMenu
    }

    Connections {
        target: BarConfig

        function onLayoutChanged() {
            bar.applyLayout();
        }

        function onHiddenChanged() {
            bar.applyLayout();
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
