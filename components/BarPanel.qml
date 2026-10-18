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
                action: () => Launcher.toggleFrom(bar.modelData.name, launcherPill, "all")
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
            Clock {
                onClicked: {
                    calPopup.preferredAnchor = clockPill;
                    Popups.toggle("calendar", bar.modelData.name);
                }
            }
        }

        Pill {
            id: weatherPill
            visible: Weather.available
            WeatherPill {
                id: weatherItem
                onClicked: {
                    calPopup.preferredAnchor = weatherPill;
                    Popups.toggle("calendar", bar.modelData.name);
                }
            }
        }

        Pill {
            id: mediaPill
            visible: mediaItem.hasPlayer
            MprisPill {
                id: mediaItem
                onClicked: Popups.toggle("media", bar.modelData.name)
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
            id: updatesPill
            visible: Updates.available
            UpdatesPill {
                id: updatesItem
                onClicked: {
                    Niri.focusMonitor(bar.modelData.name);
                    Updates.runUpdate();
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
            id: micPill
            visible: micItem.available
            Microphone {
                id: micItem
            }
        }

        Pill {
            id: keyboardPill
            visible: keyboardItem.available
            KeyboardPill {
                id: keyboardItem
            }
        }

        Pill {
            id: batteryPill
            visible: batteryItem.available
            Battery {
                id: batteryItem
                onClicked: {
                    quickPopup.preferredAnchor = batteryPill;
                    Popups.toggle("quick", bar.modelData.name);
                }
            }
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
                action: () => Niri.showHotkeyOverlay()
            }
            IconButton {
                text: "\uf013"
                fg: Theme.t2
                action: () => bar.openSettings("layout")
            }
        }

        Pill {
            id: systemPill
            IconButton {
                text: "\uf1de"
                fg: Theme.t2
                action: () => {
                    quickPopup.preferredAnchor = systemPill;
                    Popups.toggle("quick", bar.modelData.name);
                }
            }
            Bell {}
            IconButton {
                text: "⏻"
                fg: Theme.bad
                action: () => Launcher.toggleFrom(bar.modelData.name, systemPill, "power")
            }
        }

        // Tern pill (shown only when the tern app is installed): right-click moves it to the next group (saved in bar.json).
        Pill {
            id: ternPill
            visible: Tern.installed
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
        weather: weatherPill, media: mediaPill, poke: pokePill, updates: updatesPill,
        resources: resourcesPill, network: networkPill, volume: volumePill, mic: micPill,
        keyboard: keyboardPill, battery: batteryPill, tray: trayPill, tools: toolsPill,
        system: systemPill, tern: ternPill
    })

    function rowFor(side) {
        return side === "left" ? leftRow : side === "center" ? centerRow : rightRow;
    }

    // Visible 0x0 staging item used during applyLayout() so shown pills are
    // pushed onto QtQuick's LIFO dirtyItemList in reverse index order before
    // being appended to their target Row in forward index order.
    Item {
        id: staging
        width: 0
        height: 0
    }

    // Place every pill from BarConfig.layout. Detaching everything first
    // matters: setting an Item's parent to the one it already has does nothing
    // in Qt, so a pill that only changed slot inside its row would never move.
    // Staging shown pills in reverse order (n-1 .. 0) ensures QtQuick's LIFO
    // dirtyItemList pops them in forward order (0 .. n-1) during scene-graph
    // sync, so each sibling's predecessor QSGNode is already in the row's
    // container node when QSGNode::insertChildNodeAfter runs.
    function applyLayout() {
        for (const side of BarConfig.sides) {
            const list = BarConfig.layout[side] || [];
            for (let i = list.length - 1; i >= 0; i--) {
                const id = list[i];
                const pill = bar.pills[id];
                if (pill)
                    pill.parent = BarConfig.isHidden(id) ? pillStore : staging;
            }
        }
        for (const id of BarConfig.pillIds) {
            const pill = bar.pills[id];
            if (pill && pill.parent !== pillStore && pill.parent !== staging)
                pill.parent = pillStore;
        }
        for (const side of BarConfig.sides) {
            const row = bar.rowFor(side);
            const list = BarConfig.layout[side] || [];
            for (let i = 0; i < list.length; i++) {
                const id = list[i];
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

    Component.onCompleted: {
        applyLayout();
        Launcher.registerPill(bar.modelData.name, launcherPill);
    }

    // Right-click menu for the PokeToken pill (a sibling window, like TrayMenu).
    PokeMenu {
        id: pokeMenu
    }

    // The popups this bar can own (Popups decides which is open, and where).
    CalendarPopup {
        id: calPopup
        property Item preferredAnchor: null
        barWindow: bar
        screenInfo: bar.modelData
        anchorItem: (calPopup.preferredAnchor && calPopup.preferredAnchor.visible)
            ? calPopup.preferredAnchor
            : ((!BarConfig.isHidden("clock") && clockPill.visible) ? clockPill : weatherPill)
    }
    MediaPopup { barWindow: bar; screenInfo: bar.modelData; anchorItem: mediaPill }
    QuickSettings {
        id: quickPopup
        property Item preferredAnchor: null
        barWindow: bar
        screenInfo: bar.modelData
        anchorItem: (quickPopup.preferredAnchor && quickPopup.preferredAnchor.visible)
            ? quickPopup.preferredAnchor : systemPill
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
