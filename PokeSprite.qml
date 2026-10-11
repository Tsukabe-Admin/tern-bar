import QtQuick
import "singletons"

// The companion's animated sprite, frame-stepped by a timer.
//
// AnimatedImage is created with playing:false on purpose: its own player runs at
// the GIF's declared delay (often 50-100ms), which is exactly the CPU cost the
// engine's `animationQuality` setting exists to avoid. The engine computes
// `frameFloorMs` (400 powerSaver / 200 balanced / 100 smooth, forced >= 400 on
// battery saver), and this item advances one frame per tick.
Item {
    id: root

    property string sprite: ""
    property string still: ""
    property int frameFloorMs: 400
    property bool playing: true

    implicitWidth: height
    implicitHeight: 24

    AnimatedImage {
        id: animation
        anchors.fill: parent
        source: root.sprite
        playing: false
        smooth: false
        visible: root.sprite !== "" && status === Image.Ready
    }

    Image {
        anchors.fill: parent
        source: root.still
        fillMode: Image.PreserveAspectFit
        smooth: false
        visible: !animation.visible
    }

    Timer {
        interval: Math.max(100, root.frameFloorMs)
        repeat: true
        running: root.playing && animation.visible && animation.frameCount > 1
        onTriggered: animation.currentFrame = (animation.currentFrame + 1) % animation.frameCount
    }
}
