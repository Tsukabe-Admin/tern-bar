import QtQuick
import Quickshell
import "../singletons"

// Per-screen bar orchestrator: keeps persistent BarContent, PokeMenu, and
// TernMorph alive across Look swaps while lazily loading either PillsHost
// ("pills") or FrameHost ("frame").
Scope {
    id: shell

    required property var modelData

    BarContent {
        id: barContentItem
        screenInfo: shell.modelData
        screenName: shell.modelData.name
        hostWindow: hostLoader.item ? hostLoader.item.panelWindow : null

        onPokeMenuRequested: (item) => {
            const p = item.mapToItem(null, 0, 0);
            pokeMenu.barWindow = barContentItem.hostWindow;
            pokeMenu.screenInfo = shell.modelData;
            pokeMenu.anchorX = p.x;
            pokeMenu.anchorY = Theme.isFramed
                ? (Theme.barHeight + 6)
                : (Theme.barHeight + 4);
            pokeMenu.openFor(item);
        }

        onTernLaunchRequested: (item) => {
            // Open on the screen whose pill was clicked: the compositor
            // puts new windows on the focused output, and hovering the bar
            // does not change that.
            Compositor.focusMonitor(shell.modelData.name);
            if (morphLoader.item)
                morphLoader.item.launchFrom(item);
            else
                Tern.open();
        }
    }

    Component {
        id: pillsHostComp
        PillsHost {
            screenInfo: shell.modelData
            barContent: barContentItem
        }
    }

    Component {
        id: frameHostComp
        FrameHost {
            screenInfo: shell.modelData
            barContent: barContentItem
        }
    }

    Loader {
        id: hostLoader
        sourceComponent: Theme.isFramed ? frameHostComp : pillsHostComp
    }

    // Right-click menu for the PokeToken pill (a sibling window, like TrayMenu).
    PokeMenu {
        id: pokeMenu
    }

    // The morph overlay exists only while it is explicitly enabled, so the
    // bar normally never creates a second, fullscreen layer surface. It aims at
    // niri's half-width column, so it is niri only.
    Loader {
        id: morphLoader
        active: BarConfig.morphEnabled && Compositor.isNiri
        sourceComponent: Component {
            TernMorph {
                screenInfo: shell.modelData
                screenName: shell.modelData.name
            }
        }
    }
}
