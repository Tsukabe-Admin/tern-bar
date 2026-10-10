import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "singletons"

// Default sink volume pill. Click mutes, wheel steps 2%, right click opens
// pavucontrol. Glyphs match the waybar wireplumber module.
BarItem {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: (root.sink && root.sink.audio) ? root.sink.audio.volume : 0
    readonly property bool muted: (root.sink && root.sink.audio) ? root.sink.audio.muted : false

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    text: root.muted ? "󰝟 Muted"
        : (root.vol < 0.34 ? "󰕿" : root.vol < 0.67 ? "󰖀" : "󰕾")
          + " " + Math.round(root.vol * 100) + "%"
    fg: root.muted ? Theme.t3 : Theme.t1

    onClicked: {
        if (root.sink && root.sink.audio)
            root.sink.audio.muted = !root.sink.audio.muted;
    }
    onRightClicked: Quickshell.execDetached(["pavucontrol"])
    onScrolled: (delta) => {
        if (root.sink && root.sink.audio)
            root.sink.audio.volume = Math.max(0, Math.min(1, root.sink.audio.volume + 0.02 * delta));
    }
}
