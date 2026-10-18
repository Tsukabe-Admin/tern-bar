import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../singletons"

// Default audio source (microphone) pill. Click mutes/unmutes, wheel steps
// input volume by 2%, right-click opens pavucontrol. Hidden when PipeWire
// reports no default audio source.
BarItem {
    id: root

    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool available: root.source !== null && root.source.audio !== null
    readonly property real vol: root.available ? root.source.audio.volume : 0
    readonly property bool muted: root.available ? root.source.audio.muted : false

    PwObjectTracker {
        objects: root.source ? [root.source] : []
    }

    text: root.muted ? "󰍭 Muted" : "󰍬 " + Math.round(root.vol * 100) + "%"
    fg: root.muted ? Theme.t3 : Theme.t1

    onClicked: {
        if (root.available)
            root.source.audio.muted = !root.source.audio.muted;
    }
    onRightClicked: Quickshell.execDetached(["pavucontrol"])
    onScrolled: (delta) => {
        if (root.available)
            root.source.audio.volume = Math.max(0, Math.min(1, root.source.audio.volume + 0.02 * delta));
    }
}
