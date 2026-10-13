import QtQuick
import "../singletons"

// The wallpaper picker, as the settings window's "Wallpaper" tab: a thumbnail
// grid on the left for choosing an image, and the controls on the right for how
// it is drawn, what colours the desktop takes from it, and whether it rotates.
//
// Every change goes through the Wallpaper singleton, which writes
// ~/.config/niri/wallpaper.json and runs the niri scripts that act on it.
Item {
    id: page

    anchors.fill: parent

    // Which screen the grid is picking for: "*" for All screens, else an output
    // name. A screen with no image of its own follows "*".
    property string target: "*"
    property string query: ""
    property bool favoritesOnly: false

    readonly property string prettyFolder: {
        const home = Wallpaper.home;
        const folder = Wallpaper.settings.folder;
        return (home !== "" && folder.indexOf(home) === 0) ? "~" + folder.slice(home.length) : folder;
    }

    // Theme.card as "#rrggbb", for the edge-colour swatch.
    readonly property string cardHex: {
        const c = Theme.card;
        const byte = (v) => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0");
        return "#" + byte(c.r) + byte(c.g) + byte(c.b);
    }

    // The grid's contents: filtered by the search box and the favourites chip,
    // then favourites first and each group in the chosen order.
    readonly property var shown: {
        const needle = page.query.trim().toLowerCase();
        let list = Wallpaper.files;

        if (needle !== "")
            list = list.filter((f) => f.name.toLowerCase().indexOf(needle) !== -1);
        if (page.favoritesOnly)
            list = list.filter((f) => Wallpaper.isFavorite(f.path));

        const order = (Wallpaper.settings.sort === "newest")
            ? (a, b) => b.mtime - a.mtime
            : (a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase());

        return list.filter((f) => Wallpaper.isFavorite(f.path)).sort(order)
            .concat(list.filter((f) => !Wallpaper.isFavorite(f.path)).sort(order));
    }

    Component.onCompleted: {
        Wallpaper.rescan();
        // Later than the window's own focus grab, which would otherwise win.
        Qt.callLater(() => searchField.forceActiveFocus());
    }

    component SectionTitle: Text {
        color: Theme.t3
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
    }

    // ── Left: the grid and what narrows it ─────────────────────────────────
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

        Row {
            id: screenRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 8

            Chip {
                text: "All screens"
                selected: page.target === "*"
                onClicked: page.target = "*"
            }

            Repeater {
                model: Wallpaper.screens

                delegate: Chip {
                    required property string modelData
                    text: modelData
                    selected: page.target === modelData
                    onClicked: page.target = modelData
                }
            }

            Chip {
                visible: page.target !== "*" && Wallpaper.hasOwn(page.target)
                text: "Follow All screens"
                onClicked: Wallpaper.followAll(page.target)
            }
        }

        Text {
            id: screenHint
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: screenRow.bottom
            anchors.topMargin: 8
            text: (page.target === "*")
                ? "Picking for All screens replaces every screen's own wallpaper and sets the colours."
                : "Only " + page.target + " changes; colours stay with All screens."
            elide: Text.ElideRight
            color: Theme.t3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Row {
            id: searchRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: screenHint.bottom
            anchors.topMargin: 14
            spacing: 8

            Rectangle {
                id: searchBox
                width: 240
                height: 32
                radius: height / 2
                color: Theme.popBg
                border.width: 1
                border.color: Theme.rim

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchField.text === ""
                    text: "Search wallpapers"
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                TextInput {
                    id: searchField
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    selectByMouse: true
                    color: Theme.t1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize

                    onTextChanged: page.query = text

                    // Esc clears a search first; with the field already empty it
                    // is left for the window, which closes on it.
                    Keys.onEscapePressed: (event) => {
                        if (text !== "") {
                            text = "";
                            event.accepted = true;
                        } else {
                            event.accepted = false;
                        }
                    }
                }
            }

            Chip {
                text: "Name"
                selected: Wallpaper.settings.sort === "name"
                onClicked: Wallpaper.setSort("name")
            }

            Chip {
                text: "Newest"
                selected: Wallpaper.settings.sort === "newest"
                onClicked: Wallpaper.setSort("newest")
            }

            Chip {
                text: "★ Favourites"
                selected: page.favoritesOnly
                onClicked: page.favoritesOnly = !page.favoritesOnly
            }

            Chip {
                text: "Shuffle"
                onClicked: Wallpaper.shuffle(page.target, page.shown.map((f) => f.path))
            }
        }

        Text {
            id: folderText
            anchors.left: parent.left
            anchors.right: changeFolder.left
            anchors.rightMargin: 12
            anchors.top: searchRow.bottom
            anchors.topMargin: 18
            text: page.prettyFolder + " · " + Wallpaper.files.length + " images"
            elide: Text.ElideMiddle
            color: Theme.t2
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Chip {
            id: changeFolder
            anchors.right: parent.right
            anchors.verticalCenter: folderText.verticalCenter
            text: "Change folder…"
            onClicked: Wallpaper.chooseFolder()
        }

        GridView {
            id: grid
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: folderText.bottom
            anchors.bottom: errorLine.top
            anchors.topMargin: 14
            anchors.bottomMargin: 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: page.shown

            readonly property int columns: Math.max(1, Math.floor(width / 220))
            cellWidth: Math.floor(width / columns)
            cellHeight: Math.round(cellWidth * 0.625)

            delegate: WallpaperTile {
                required property var modelData
                path: modelData.path
                name: modelData.name
                target: page.target
                width: grid.cellWidth
                height: grid.cellHeight
            }
        }

        Text {
            anchors.centerIn: grid
            visible: grid.count === 0
            text: (Wallpaper.files.length === 0)
                ? "No images in " + page.prettyFolder
                : "Nothing matches"
            color: Theme.t2
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Text {
            id: errorLine
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: text !== "" ? implicitHeight : 0
            text: Wallpaper.lastError
            elide: Text.ElideRight
            color: Theme.bad
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }

    // ── Right: everything about how it is drawn and coloured ───────────────
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

            // Fill ─────────────────────────────────────────────────────────────
            Column {
                width: side.width
                spacing: 8

                SectionTitle { text: "Fill" }

                Flow {
                    width: side.width
                    spacing: 6

                    Repeater {
                        model: Wallpaper.fills

                        delegate: Chip {
                            required property string modelData
                            required property int index
                            text: Wallpaper.fillNames[index]
                            selected: Wallpaper.settings.fill === modelData
                            onClicked: Wallpaper.setFill(modelData)
                        }
                    }
                }

                // Only matter when the image does not cover the screen, so they
                // are dimmed and inert under Crop and Stretch.
                Column {
                    width: side.width
                    spacing: 8
                    readonly property bool relevant: Wallpaper.settings.fill === "fit"
                        || Wallpaper.settings.fill === "center"
                    enabled: relevant
                    opacity: relevant ? 1 : 0.4

                    Text {
                        text: "Edge colour"
                        color: Theme.t3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    Row {
                        spacing: 8

                        Repeater {
                            model: ["#000000", "#ffffff", page.cardHex]

                            delegate: Rectangle {
                                required property string modelData
                                width: 22
                                height: 22
                                radius: 6
                                color: modelData
                                border.width: 1
                                border.color: Theme.rim

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Wallpaper.setFillColor(parent.modelData)
                                }
                            }
                        }

                        Rectangle {
                            width: 140
                            height: 22
                            radius: height / 2
                            color: Theme.popBg
                            border.width: 1
                            border.color: Theme.rim

                            TextInput {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.t1
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                text: Wallpaper.settings.fillColor

                                onAccepted: {
                                    if (/^#[0-9a-fA-F]{6}$/.test(text))
                                        Wallpaper.setFillColor(text);
                                    else
                                        text = Wallpaper.settings.fillColor;
                                }
                            }
                        }
                    }
                }
            }

            // Transition ───────────────────────────────────────────────────────
            Column {
                width: side.width
                spacing: 8

                SectionTitle { text: "Transition" }

                Flow {
                    width: side.width
                    spacing: 6

                    Repeater {
                        model: Wallpaper.transitions

                        delegate: Chip {
                            required property string modelData
                            required property int index
                            text: Wallpaper.transitionNames[index]
                            selected: Wallpaper.settings.transition === modelData
                            onClicked: Wallpaper.setTransition(modelData)
                        }
                    }
                }

                Text {
                    text: "Duration: " + durationSlider.shownValue.toFixed(2).replace(/0$/, "") + " s"
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                SettingsSlider {
                    id: durationSlider
                    width: side.width
                    from: 0.5
                    to: 3
                    stepSize: 0.25
                    value: Wallpaper.settings.transitionDuration
                    // awww ignores the duration for a plain fade, and "none"
                    // has no transition to time at all.
                    enabled: Wallpaper.settings.transition !== "none"
                    onCommitted: (v) => Wallpaper.setTransitionDuration(v)
                }
            }

            // Colours ──────────────────────────────────────────────────────────
            Column {
                width: side.width
                spacing: 10

                SectionTitle { text: "Colours" }

                SwitchRow {
                    id: matugenSwitch
                    width: side.width
                    text: "Colours from wallpaper (matugen)"
                    on: Wallpaper.settings.colorSource === "wallpaper"
                    // `on` is the state being left, not the one being entered:
                    // switching it off means the preset themes.
                    onToggled: Wallpaper.setColorSource(matugenSwitch.on ? "preset" : "wallpaper")
                }

                Text {
                    width: side.width
                    wrapMode: Text.WordWrap
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    text: (Wallpaper.settings.colorSource === "wallpaper")
                        ? "Colours follow the All screens wallpaper."
                        : "Pick a theme. Wallpaper changes keep these colours."
                }

                // matugen on: the scheme and contrast matugen reads the image with.
                Column {
                    width: side.width
                    spacing: 8
                    visible: Wallpaper.settings.colorSource === "wallpaper"

                    Flow {
                        width: side.width
                        spacing: 6

                        Repeater {
                            model: Wallpaper.schemes

                            delegate: Chip {
                                required property string modelData
                                required property int index
                                text: Wallpaper.schemeNames[index]
                                selected: Wallpaper.settings.scheme === modelData
                                onClicked: Wallpaper.setScheme(modelData)
                            }
                        }
                    }

                    Text {
                        text: "Contrast: " + (contrastSlider.shownValue === 0
                            ? "Standard"
                            : (contrastSlider.shownValue > 0 ? "+" : "") + contrastSlider.shownValue.toFixed(2).replace(/0$/, ""))
                        color: Theme.t3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    SettingsSlider {
                        id: contrastSlider
                        width: side.width
                        from: -1
                        to: 1
                        stepSize: 0.25
                        value: Wallpaper.settings.contrast
                        onCommitted: (v) => Wallpaper.setContrast(v)
                    }
                }

                // matugen off: one card per preset theme.
                Column {
                    width: side.width
                    spacing: 6
                    visible: Wallpaper.settings.colorSource === "preset"

                    Repeater {
                        model: Wallpaper.presets

                        delegate: Rectangle {
                            id: presetCard
                            required property var modelData

                            width: side.width
                            height: 40
                            radius: 12
                            color: modelData.surface
                            border.width: Wallpaper.settings.preset === modelData.id ? 2 : 1
                            border.color: Wallpaper.settings.preset === modelData.id
                                ? Theme.accent
                                : modelData.outlineVariant

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.right: swatches.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: presetCard.modelData.name
                                elide: Text.ElideRight
                                color: presetCard.modelData.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            Row {
                                id: swatches
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5

                                Repeater {
                                    model: [presetCard.modelData.primary, presetCard.modelData.secondary,
                                        presetCard.modelData.tertiary, presetCard.modelData.error,
                                        presetCard.modelData.fgDim]

                                    delegate: Rectangle {
                                        required property string modelData
                                        width: 12
                                        height: 12
                                        radius: height / 2
                                        color: modelData
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: Wallpaper.setPreset(presetCard.modelData.id)
                            }
                        }
                    }

                    Text {
                        width: side.width
                        wrapMode: Text.WordWrap
                        visible: Wallpaper.presets.length === 0
                        text: "No presets file at ~/.config/matugen/presets.json"
                        color: Theme.t2
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }
            }

            // Rotate ───────────────────────────────────────────────────────────
            Column {
                width: side.width
                spacing: 8

                SectionTitle { text: "Rotate" }

                SwitchRow {
                    id: rotateSwitch
                    width: side.width
                    text: "Change automatically"
                    on: Wallpaper.settings.rotate
                    onToggled: Wallpaper.setRotate(!rotateSwitch.on)
                }

                Flow {
                    width: side.width
                    spacing: 6
                    enabled: Wallpaper.settings.rotate
                    opacity: Wallpaper.settings.rotate ? 1 : 0.4

                    Repeater {
                        model: Wallpaper.rotateChoices

                        delegate: Chip {
                            required property int modelData
                            text: (modelData >= 60) ? (modelData / 60) + " h" : modelData + " min"
                            selected: Wallpaper.settings.rotateMinutes === modelData
                            onClicked: Wallpaper.setRotateMinutes(modelData)
                        }
                    }
                }

                SwitchRow {
                    id: favoritesSwitch
                    width: side.width
                    text: "Only favourites"
                    enabled: Wallpaper.settings.rotate
                    on: Wallpaper.settings.rotateFavoritesOnly
                    onToggled: Wallpaper.setRotateFavoritesOnly(!favoritesSwitch.on)
                }

                Text {
                    width: side.width
                    wrapMode: Text.WordWrap
                    text: "Changes the All screens wallpaper; screens with their own keep it."
                    color: Theme.t3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }
}
