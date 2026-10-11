import QtQuick
import "../singletons"

// The bar pill: companion sprite + the engine's precomputed menu-bar parts
// (today's tokens, cost, each official-limit "Claude NN%").
//
// Colours come from status.json: a part carries a pace tier when the user's
// `menuLimitColorMode` asks for it (gauge = every limit, attention = only limits
// running faster than pace, off = none); the pill only maps tier -> colour, so the
// pane, the pill and the pet can never disagree about what "over pace" means.
//
// Clicks are handled by one MouseArea over the whole item rather than by the
// BarItems inside (a MouseArea is a plain QObject handler that needs no anchors
// inside a Row, and it makes the sprite clickable too).
Item {
    id: root

    property var launch: null          // left click (BarPanel focuses this output first)
    property var menuRequested: null   // right click; called with this item as the anchor

    readonly property var parts: (Poke.status && Poke.status.parts) ? Poke.status.parts : []
    readonly property var status: Poke.status

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    function tierColor(tier) {
        switch (tier) {
        case "wayUnder": return Theme.accent;      // #2979ff
        case "under": return Theme.live;           // #00e5ff
        case "onPace": return Theme.ok;            // #00e676
        case "slightlyOver": return Theme.warn;    // #ffea00
        case "over": return "#FF9100";
        case "wayOver": return Theme.bad;          // #ff1744
        }
        return Poke.stale ? Theme.t3 : Theme.t1;
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        Item {
            implicitWidth: 4
            implicitHeight: 1
        }

        PokeSprite {
            id: sprite
            height: 24
            anchors.verticalCenter: parent.verticalCenter
            sprite: root.status ? (root.status.sprite || "") : ""
            still: root.status ? (root.status.still || "") : ""
            frameFloorMs: root.status ? (root.status.frameFloorMs || 400) : 400
            opacity: Poke.stale ? 0.55 : 1.0
        }

        Repeater {
            model: root.parts

            delegate: Row {
                required property int index
                required property var modelData

                spacing: 5

                Text {
                    visible: index > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: "·"
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                BarItem {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.text
                    fg: root.tierColor(modelData.tier)
                }
            }
        }

        Item {
            implicitWidth: 4
            implicitHeight: 1
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                if (root.menuRequested)
                    root.menuRequested(root);
            } else if (root.launch) {
                root.launch();
            }
        }
    }
}
