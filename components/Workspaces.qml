import QtQuick
import "../singletons"

// Workspace chips for one output, ordered by idx. Clicking focuses by
// workspace Id (indices collide across outputs).
Row {
    id: root

    property string output: ""
    spacing: 0

    Repeater {
        model: Compositor.workspacesFor(root.output)

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
        }
    }
}
