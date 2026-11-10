pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland

// Keep awake: while on, the screen does not dim, lock or sleep on its own
// (the quick-settings tile; a coffee cup on the bar says it is on). It asks the
// compositor through the idle-inhibit protocol, which needs a surface: a
// 1x1 click-through window that exists only while keep-awake is on.
Singleton {
    id: root

    readonly property bool on: state.on

    function toggle() {
        state.on = !state.on;
    }

    // Survives hot reloads, not restarts: a forgotten toggle ends at the next login.
    PersistentProperties {
        id: state
        reloadableId: "keepAwake"
        property bool on: false
    }

    // On the overlay layer: niri counts an inhibitor only while its surface is
    // drawn, and the overlay layer stays drawn above fullscreen windows, where
    // the bar does not.
    LazyLoader {
        active: state.on

        PanelWindow {
            id: holder

            // Set at the window's first frame.
            property bool drawn: false

            screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
            anchors.top: true
            anchors.left: true
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            mask: Region {}
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "tern-keepawake"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Hyprland looks at an inhibitor when it is made and when focus or
            // windows change, not when a layer surface first appears. Made
            // together with the surface, before its first frame, it would not
            // count there until the next focus change; made after that frame it
            // counts at once.
            Connections {
                target: holder.contentItem.Window.window
                enabled: !holder.drawn

                function onFrameSwapped() {
                    holder.drawn = true;
                }
            }

            IdleInhibitor {
                window: holder
                enabled: holder.drawn
            }
        }
    }
}
