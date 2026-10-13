import QtQuick
import Quickshell
import Quickshell.Io
import "components"
import "singletons"

ShellRoot {
    Variants {
        model: Quickshell.screens

        delegate: Component {
            BarPanel {}
        }
    }

    // One floating pet, on the output the engine's settings name (layer surfaces
    // cannot be dragged across outputs, so "Move to next screen" writes the
    // setting instead of moving the window).
    Loader {
        active: !!(Poke.status && Poke.status.pet && Poke.status.pet.enabled)
        sourceComponent: Component {
            PokePet {}
        }
    }

    // The settings page is a single window for the whole shell — not one per
    // screen — created while it is open and destroyed when it closes.
    Loader {
        active: BarConfig.settingsOpen
        sourceComponent: Component {
            SettingsWindow {}
        }
    }

    IpcHandler {
        target: "settings"

        // Mod+B and the gear: the layout editor.
        function toggle(): void {
            BarConfig.toggleSettings("layout");
        }

        function open(): void {
            BarConfig.openSettings("layout");
        }

        // Mod+W and the tools pill's wallpaper button.
        function wallpaper(): void {
            BarConfig.toggleSettings("wallpaper");
        }

        function close(): void {
            BarConfig.settingsOpen = false;
        }
    }

    // Singletons are built the first time something uses them, so without this
    // the rotation timer and the screen hotplug handler would not exist until
    // the Wallpaper tab had been opened once.
    Component.onCompleted: Wallpaper.rescan()
}
