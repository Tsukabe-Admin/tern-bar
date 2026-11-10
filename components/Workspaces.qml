import QtQuick
import "../singletons"

// Workspace chips for one output, ordered by idx. Clicking focuses by
// workspace Id (indices collide across outputs); the wheel steps to the
// workspace above or below. niri always keeps one empty workspace at the end
// of each output: its chip is left out unless it is the active one, and
// scrolling down from the last chip still reaches it. On Hyprland, a
// scratchpad (special workspace) open on this output adds one more chip,
// which hides it again.
Row {
    id: root

    property string output: ""
    spacing: 0

    readonly property var all: Compositor.workspacesFor(root.output)
    readonly property var shown: root.all.filter((ws, i) => !(Compositor.isNiri && i === root.all.length - 1
        && ws.active_window_id === null && !ws.is_active))
    readonly property string special: Compositor.specialWorkspaceOn(root.output)

    // Wheel up: the workspace above; wheel down: the one below.
    function step(delta) {
        if (scrollCooldown.running)
            return;
        const i = root.all.findIndex((ws) => ws.is_active);
        const j = i + (delta > 0 ? -1 : 1);
        if (i === -1 || j < 0 || j >= root.all.length)
            return;
        Compositor.focusWorkspace(root.all[j].id);
        scrollCooldown.restart();
    }

    // A touchpad swipe sends many wheel events: one step per 200 ms.
    Timer {
        id: scrollCooldown
        interval: 200
    }

    Repeater {
        model: root.shown

        delegate: BarItem {
            required property var modelData

            text: modelData.is_urgent ? "󰀦"
                : modelData.is_focused ? "󰮯"
                : modelData.is_active ? "󰊠"
                : "•"
            fg: modelData.is_urgent ? Theme.bad
                : modelData.is_focused ? Theme.accent
                : modelData.is_active ? Theme.t2
                : Theme.t3
            onClicked: Compositor.focusWorkspace(modelData.id)
            onScrolled: (delta) => root.step(delta)
        }
    }

    BarItem {
        visible: root.special !== ""
        text: "󰌨"
        fg: Theme.accent
        onClicked: Compositor.toggleSpecialWorkspace(root.special)
    }
}
