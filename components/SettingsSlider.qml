import QtQuick
import "../singletons"

// A horizontal slider that only reports on release. While it is being dragged the
// caller reads shownValue for its label; the value itself changes only through
// committed(), so one drag is one run of a script rather than a dozen.
Item {
    id: root

    property real from: 0
    property real to: 1
    property real stepSize: 0.25
    property real value: 0

    signal committed(real value)

    property bool dragging: false
    property real liveValue: root.value

    readonly property real shownValue: root.dragging ? root.liveValue : root.value
    readonly property real fraction: (root.to > root.from)
        ? Math.max(0, Math.min(1, (root.shownValue - root.from) / (root.to - root.from)))
        : 0

    implicitHeight: 24
    height: implicitHeight
    width: parent ? parent.width : 0
    opacity: root.enabled ? 1 : 0.4

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 4
        radius: height / 2
        color: Theme.l3
    }

    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: track.height
        radius: track.radius
        color: Theme.accent
        width: Math.max(0, root.fraction * track.width)
    }

    Rectangle {
        id: handle
        width: 14
        height: 14
        radius: height / 2
        color: Theme.t1
        anchors.verticalCenter: parent.verticalCenter
        // Stays fully inside the track at both ends.
        x: Math.max(0, Math.min(parent.width - width, root.fraction * parent.width - width / 2))
    }

    MouseArea {
        anchors.fill: parent

        onPressed: (mouse) => {
            // Seed from the stored value: liveValue stops following `value` the
            // first time it is assigned, so each drag re-seeds itself.
            root.liveValue = root.value;
            root.dragging = true;
            apply(mouse.x);
        }

        onPositionChanged: (mouse) => {
            if (root.dragging)
                apply(mouse.x);
        }

        onReleased: {
            root.dragging = false;
            root.committed(root.liveValue);
        }

        function apply(px) {
            const span = root.to - root.from;
            if (span <= 0 || root.width <= 0)
                return;
            const raw = root.from + Math.max(0, Math.min(1, px / root.width)) * span;
            const snapped = (root.stepSize > 0)
                ? root.from + Math.round((raw - root.from) / root.stepSize) * root.stepSize
                : raw;
            root.liveValue = Math.max(root.from, Math.min(root.to, snapped));
        }
    }
}
