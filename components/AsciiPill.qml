import QtQuick
import "../singletons"

// A few characters of ambient animation (waves, embers, stars, rain) in the
// bar. Left-click moves to the next piece; right-click opens the ASCII tab,
// where the piece, its colour and its speed are chosen (singletons/Ascii.qml).
// The frames come from tools/ascii/gen.mjs.
BarItem {
    id: root

    implicitWidth: art.implicitWidth + 2 * root.sidePadding
    fg: Ascii.pillColor

    onClicked: Ascii.cyclePillPiece(1)
    onRightClicked: BarConfig.openSettings("ascii")

    AsciiArt {
        id: art
        anchors.centerIn: parent
        name: "pill-" + Ascii.settings.pill.piece
        tint: root.fg
        speed: Ascii.pillSpeedFactor
    }
}
