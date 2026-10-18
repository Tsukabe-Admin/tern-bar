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

    // The launcher card: one window for the whole shell, kept alive between
    // openings so opening costs no QML compilation and icons stay cached.
    LauncherWindow {}

    // Volume and Brightness OSDs: one surface each for the whole shell, shown
    // near the bottom of the focused screen when volume or brightness changes.
    VolumeOsd {}
    BrightnessOsd {}

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

    // Keyboard shortcuts: quickshell ipc -c tern-bar call launcher <toggle|clipboard|power|close>
    IpcHandler {
        target: "launcher"

        function toggle(): void {
            Launcher.toggleOnFocused("all", "");
        }

        function clipboard(): void {
            Launcher.toggleOnFocused("all", ";");
        }

        function power(): void {
            Launcher.toggleOnFocused("power", "");
        }

        function close(): void {
            Launcher.close();
        }
    }

    // The terminal shortcut (Mod+Return, Mod+T): the same launch as the pill,
    // so the tab opens in a window that is brought forward first.
    IpcHandler {
        target: "tern"

        function open(): void {
            Tern.open();
        }
    }

    // quickshell ipc -c tern-bar call bar <calendar|media|quickSettings|close>
    IpcHandler {
        target: "bar"

        function calendar(): void {
            Popups.toggle("calendar", Popups.focusedScreenName());
        }

        function media(): void {
            Popups.toggle("media", Popups.focusedScreenName());
        }

        function quickSettings(): void {
            Popups.toggle("quick", Popups.focusedScreenName());
        }

        function close(): void {
            Popups.close();
        }
    }

    // Singletons are built the first time something uses them, so without this
    // the rotation timer and the screen hotplug handler would not exist until
    // the Wallpaper tab had been opened once. NightLight, Brightness, Weather
    // and Updates likewise.
    Component.onCompleted: {
        Wallpaper.rescan();
        NightLight.available;
        Brightness.available;
        Weather.wanted;
        Updates.wanted;
    }
}
