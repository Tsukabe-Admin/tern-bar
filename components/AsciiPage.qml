import QtQuick
import "../singletons"

// The ASCII animation studio, as the settings window's "ASCII" tab: a grid of
// looks on the left, and on the right the colour, speed, size and brightness of
// the animated wallpaper plus the piece, colour and speed of the bar's pill.
//
// Choices go through the Ascii singleton, which writes ~/.config/tern-bar/ascii.json.
// The previews are played live; the wallpaper is a GIF, so it only changes when
// "Render & set wallpaper" has run scripts/ascii-render.sh.
Item {
    id: page

    anchors.fill: parent

    readonly property string prettyFolder: {
        const home = Wallpaper.home;
        const folder = Wallpaper.settings.folder + "/ascii";
        return (home !== "" && folder.indexOf(home) === 0) ? "~" + folder.slice(home.length) : folder;
    }

    function title(id) {
        return id.charAt(0).toUpperCase() + id.slice(1);
    }

    component SectionTitle: Text {
        textFormat: Text.PlainText
        color: Theme.t3
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
    }

    // A Chip with a colour dot in front of its label.
    component SwatchChip: Rectangle {
        id: swatch

        property string label: ""
        property color dot: Theme.accent
        property bool selected: false

        signal clicked

        implicitWidth: swatchRow.implicitWidth + 24
        implicitHeight: 30
        width: implicitWidth
        height: implicitHeight
        radius: height / 2
        color: swatch.selected ? Qt.alpha(Theme.accent, 0.18) : Theme.popBg
        border.width: 1
        border.color: swatch.selected ? Theme.accent : Theme.rim
        opacity: swatch.enabled ? 1 : 0.4

        Behavior on color {
            ColorAnimation { duration: Theme.motionFast }
        }

        Behavior on border.color {
            ColorAnimation { duration: Theme.motionFast }
        }

        Rectangle {
            anchors.fill: parent
            radius: swatch.radius
            color: Theme.hover
            opacity: (swatchHover.hovered && swatch.enabled) ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.motionFast
                    easing.type: Easing.OutCubic
                }
            }
        }

        Row {
            id: swatchRow
            anchors.centerIn: parent
            spacing: 7

            Rectangle {
                width: 12
                height: 12
                radius: 6
                anchors.verticalCenter: parent.verticalCenter
                color: swatch.dot
                border.width: 1
                border.color: Theme.rim
            }

            Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: swatch.label
                color: swatch.selected ? Theme.t1 : Theme.t2
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }

        HoverHandler {
            id: swatchHover
        }

        MouseArea {
            anchors.fill: parent
            onClicked: swatch.clicked()
        }
    }

    // Theme, every palette and Custom as swatch chips, and under them the hex
    // field while Custom is chosen. Used for both the wallpaper and the pill.
    component ColourPicker: Column {
        id: picker

        property string current: "theme"
        property string custom: "#7aa2f7"

        signal picked(string key)
        signal customPicked(string hex)

        width: 300
        spacing: 8

        Flow {
            width: picker.width
            spacing: 6

            SwatchChip {
                label: "Theme"
                dot: Theme.accent
                selected: picker.current === "theme"
                onClicked: picker.picked("theme")
            }

            Repeater {
                model: Ascii.manifest.palettes

                delegate: SwatchChip {
                    required property var modelData
                    label: modelData.name
                    dot: modelData.accent
                    selected: picker.current === modelData.id
                    onClicked: picker.picked(modelData.id)
                }
            }

            SwatchChip {
                label: "Custom"
                dot: picker.custom
                selected: picker.current === "custom"
                onClicked: picker.picked("custom")
            }
        }

        Rectangle {
            visible: picker.current === "custom"
            width: 140
            height: 26
            radius: height / 2
            color: Theme.popBg
            border.width: 1
            border.color: Theme.rim

            TextInput {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.t1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                text: picker.custom

                onAccepted: {
                    if (/^#[0-9a-fA-F]{6}$/.test(text))
                        picker.customPicked(text);
                    else
                        text = picker.custom;
                }
            }
        }
    }

    // ── Left: the looks ────────────────────────────────────────────────────
    Item {
        id: main
        anchors.left: parent.left
        anchors.right: sidebar.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.topMargin: 16
        anchors.bottomMargin: 24

        Text {
            textFormat: Text.PlainText
            id: hint
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            text: "Pick a look and colours, then Render to make it the All screens wallpaper."
            elide: Text.ElideRight
            color: Theme.t3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        GridView {
            id: grid
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: hint.bottom
            anchors.bottom: parent.bottom
            anchors.topMargin: 14
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: Ascii.manifest.looks
            cellWidth: 196
            cellHeight: 124

            delegate: Rectangle {
                id: tile

                required property var modelData
                readonly property bool chosen: Ascii.settings.wallpaper.look === tile.modelData.id

                width: 184
                height: 112
                radius: 12
                color: Ascii.wallpaperBackground
                border.width: tile.chosen ? 2 : 1
                border.color: tile.chosen ? Theme.accent : Theme.rim
                clip: true

                AsciiArt {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -8
                    name: "preview-" + tile.modelData.id
                    tint: Ascii.wallpaperTint
                    speed: Ascii.wallpaperSpeedFactor
                    pixelSize: 10
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 10
                    anchors.bottomMargin: 8
                    text: tile.modelData.name
                    color: Theme.t2
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Ascii.setLook(tile.modelData.id)
                }
            }
        }

        Text {
            textFormat: Text.PlainText
            anchors.centerIn: grid
            visible: Ascii.manifest.looks.length === 0
            text: "Couldn't read assets/ascii/manifest.json"
            color: Theme.t2
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }

    // ── Right: wallpaper and pill controls ─────────────────────────────────
    Flickable {
        id: sidebar
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.topMargin: 16
        anchors.bottomMargin: 24
        width: 300
        clip: true
        contentHeight: side.height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
            id: side
            width: sidebar.width
            spacing: 18

            // Colour ───────────────────────────────────────────────────────────
            Column {
                width: side.width
                spacing: 8

                SectionTitle { text: "Colour" }

                ColourPicker {
                    width: side.width
                    current: Ascii.settings.wallpaper.palette
                    custom: Ascii.settings.wallpaper.custom
                    onPicked: (key) => Ascii.setPalette(key)
                    onCustomPicked: (hex) => Ascii.setCustom(hex)
                }
            }

            // Speed ────────────────────────────────────────────────────────────
            Column {
                width: side.width
                spacing: 8

                SectionTitle { text: "Speed" }

                Flow {
                    width: side.width
                    spacing: 6

                    Repeater {
                        model: Ascii.manifest.wallpaperSpeeds

                        delegate: Chip {
                            required property string modelData
                            text: page.title(modelData)
                            selected: Ascii.settings.wallpaper.speed === modelData
                            onClicked: Ascii.setSpeed(modelData)
                        }
                    }
                }
            }

            // Size ─────────────────────────────────────────────────────────────
            Column {
                width: side.width
                spacing: 8

                SectionTitle { text: "Size" }

                Flow {
                    width: side.width
                    spacing: 6

                    Repeater {
                        model: Ascii.manifest.sizes

                        delegate: Chip {
                            required property string modelData
                            text: page.title(modelData)
                            selected: Ascii.settings.wallpaper.size === modelData
                            onClicked: Ascii.setSize(modelData)
                        }
                    }
                }
            }

            // Brightness ───────────────────────────────────────────────────────
            Column {
                width: side.width
                spacing: 8

                SectionTitle { text: "Brightness: " + Math.round(brightnessSlider.shownValue * 100) + "%" }

                SettingsSlider {
                    id: brightnessSlider
                    width: side.width
                    from: 0.3
                    to: 1
                    stepSize: 0.1
                    value: Ascii.settings.wallpaper.brightness
                    onCommitted: (v) => Ascii.setBrightness(v)
                }
            }

            // Render ───────────────────────────────────────────────────────────
            Column {
                width: side.width
                spacing: 8

                SectionTitle { text: "Wallpaper" }

                Chip {
                    text: Ascii.rendering ? "Rendering…" : "Render & set wallpaper"
                    enabled: !Ascii.rendering
                    onClicked: Ascii.render()
                }

                Text {
                    textFormat: Text.PlainText
                    width: side.width
                    visible: text !== ""
                    wrapMode: Text.WordWrap
                    text: Ascii.lastError !== "" ? Ascii.lastError : Ascii.status
                    color: Ascii.lastError !== "" ? Theme.bad : Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Text {
                    textFormat: Text.PlainText
                    width: side.width
                    wrapMode: Text.WordWrap
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    text: "Takes 15–45 s. Saved in " + page.prettyFolder + "/."
                        + (Wallpaper.settings.colorSource === "wallpaper"
                            ? " Colours from wallpaper is on, so the bar recolours to match."
                            : "")
                }
            }

            // Bar pill ─────────────────────────────────────────────────────────
            Column {
                width: side.width
                spacing: 8

                SectionTitle { text: "Bar pill" }

                Rectangle {
                    width: pillArt.implicitWidth + 32
                    height: 32
                    radius: 16
                    color: Theme.popBg
                    border.width: 1
                    border.color: Theme.rim

                    AsciiArt {
                        id: pillArt
                        anchors.centerIn: parent
                        name: "pill-" + Ascii.settings.pill.piece
                        tint: Ascii.pillColor
                        speed: Ascii.pillSpeedFactor
                    }
                }

                Flow {
                    width: side.width
                    spacing: 6

                    Repeater {
                        model: Ascii.manifest.pillPieces

                        delegate: Chip {
                            required property var modelData
                            text: modelData.name
                            selected: Ascii.settings.pill.piece === modelData.id
                            onClicked: Ascii.setPillPiece(modelData.id)
                        }
                    }
                }

                ColourPicker {
                    width: side.width
                    current: Ascii.settings.pill.color
                    custom: Ascii.settings.pill.custom
                    onPicked: (key) => Ascii.setPillColor(key)
                    onCustomPicked: (hex) => Ascii.setPillCustom(hex)
                }

                Flow {
                    width: side.width
                    spacing: 6

                    Repeater {
                        model: Ascii.manifest.pillSpeeds

                        delegate: Chip {
                            required property string modelData
                            text: page.title(modelData)
                            selected: Ascii.settings.pill.speed === modelData
                            onClicked: Ascii.setPillSpeed(modelData)
                        }
                    }
                }
            }
        }
    }
}
