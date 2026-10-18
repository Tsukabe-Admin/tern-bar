import QtQuick
import "../singletons"

// Pending Arch/Pacman/AUR package updates pill. Hidden when 0 updates are
// available or when neither checkupdates nor pacman is installed. Left-click
// opens a terminal to run the system upgrade; right-click re-checks now.
BarItem {
    id: root

    text: "󰏗 " + Updates.count
    fg: Theme.accent

    onRightClicked: Updates.refresh()
}
