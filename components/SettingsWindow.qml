import QtQuick
import Quickshell
import "../singletons"

// tern-bar's settings window: two tabs, switched by the chips at the top-left.
//
//   Layout     the bar's pill layout — opened by the tools pill's gear, a
//              right-click on the launcher, or Mod+B
//   Wallpaper  the wallpaper picker and colour controls — opened by Mod+W or
//              the tools pill's wallpaper button
//
// Closed with Esc or the window's own close button. Only the visible tab is
// built, so the wallpaper grid does not decode thumbnails while you are looking
// at the layout.
FloatingWindow {
    id: win

    title: "tern-bar settings"
    visible: true
    implicitWidth: 1120
    implicitHeight: 720
    minimumSize: Qt.size(860, 560)
    color: Theme.card

    // Closing through niri (Mod+Q, the close button) is not routed through this
    // side, so both paths have to switch the settings page off.
    onClosed: BarConfig.settingsOpen = false
    onVisibleChanged: {
        if (!win.visible)
            BarConfig.settingsOpen = false;
    }

    FocusScope {
        id: frame
        anchors.fill: parent
        focus: true

        Component.onCompleted: frame.forceActiveFocus()

        // A page that wants Esc for itself — the wallpaper search field with
        // text in it — accepts the key before it reaches here.
        Keys.onEscapePressed: BarConfig.settingsOpen = false

        Row {
            id: tabs
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: 24
            anchors.topMargin: 24
            spacing: 8

            Chip {
                text: "Layout"
                selected: BarConfig.settingsTab === "layout"
                onClicked: BarConfig.settingsTab = "layout"
            }

            Chip {
                text: "Wallpaper"
                selected: BarConfig.settingsTab === "wallpaper"
                onClicked: BarConfig.settingsTab = "wallpaper"
            }
        }

        Loader {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: tabs.bottom
            anchors.bottom: parent.bottom
            active: BarConfig.settingsTab === "layout"
            sourceComponent: Component {
                LayoutPage {}
            }
        }

        Loader {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: tabs.bottom
            anchors.bottom: parent.bottom
            active: BarConfig.settingsTab === "wallpaper"
            sourceComponent: Component {
                WallpaperPage {}
            }
        }
    }
}
