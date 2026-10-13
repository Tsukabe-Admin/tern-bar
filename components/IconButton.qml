import QtQuick

// Single-glyph action button (launcher, wallpaper, cheatsheet, settings, power).
BarItem {
    id: root

    property var action: null
    property var rightAction: null

    onClicked: {
        if (root.action)
            root.action();
    }

    onRightClicked: {
        if (root.rightAction)
            root.rightAction();
    }
}
