pragma Singleton

import QtQuick
import Quickshell

// A short message from the bar itself, such as "IP address hidden", shown by
// components/NoticeOsd.qml for two seconds near the bottom of the focused screen.
// It takes the place of notify-send: no outside program, and a confirmation like
// this one never lands in the notification history.
Singleton {
    id: root

    property string icon: ""
    property string text: ""
    // Bumped by every show(), so the same message twice in a row shows twice.
    property int serial: 0

    // `icon` is one Nerd Font glyph; `text` is plain text.
    function show(icon, text) {
        root.icon = icon;
        root.text = text;
        root.serial++;
    }
}
