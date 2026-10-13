import QtQuick
import "../singletons"

// The capsule on/off switch. Lifted out of the layout rows so the wallpaper
// page's switches cannot drift away from theirs.
Rectangle {
    id: root

    property bool on: false

    implicitWidth: 34
    implicitHeight: 18
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: root.on ? Theme.accent : Theme.l3

    Behavior on color {
        ColorAnimation { duration: Theme.motionFast }
    }

    Rectangle {
        y: 2
        width: 14
        height: 14
        radius: height / 2
        color: Theme.t1
        x: root.on ? parent.width - width - 2 : 2

        Behavior on x {
            NumberAnimation {
                duration: Theme.motionFast
                easing.type: Easing.OutCubic
            }
        }
    }
}
