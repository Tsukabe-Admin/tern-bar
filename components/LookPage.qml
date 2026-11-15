pragma ComponentBehavior: Bound

import QtQuick
import "../singletons"

// Look selector & Frame customization tab for SettingsWindow.
Item {
    id: page

    anchors.fill: parent

    // One card per Look, in Looks' order, with the title and summary kept there.
    readonly property var lookCards: Looks.available.map((id) => Looks.metadata[id])

    Column {
        id: header
        anchors.left: parent.left
        anchors.right: resetBtn.left
        anchors.top: parent.top
        anchors.leftMargin: 24
        anchors.rightMargin: 16
        anchors.topMargin: 20
        spacing: 4

        Text {
            textFormat: Text.PlainText
            text: "Bar look"
            color: Theme.t1
            font.family: Theme.fontFamily
            font.pixelSize: 20
            font.bold: true
        }

        Text {
            textFormat: Text.PlainText
            text: "Choose how tern-bar sits on every monitor. Saved immediately to bar.json."
            color: Theme.t2
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
            width: parent.width
        }
    }

    Chip {
        id: resetBtn
        visible: Looks.isFramed
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 24
        anchors.topMargin: 20
        text: "Reset Frame"
        onClicked: BarConfig.resetLookOptions()
    }

    Flickable {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.topMargin: 16
        anchors.bottomMargin: 20
        contentWidth: width
        contentHeight: bodyCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: bodyCol
            width: parent.width
            spacing: 18

            // ── Look Style Selector ───────────────────────────────────────────
            Row {
                width: parent.width
                spacing: 14

                Repeater {
                    model: page.lookCards

                    delegate: Rectangle {
                        id: card
                        required property var modelData

                        readonly property bool selected: Looks.activeId === card.modelData.id
                        readonly property bool isFrameCard: card.modelData.id === "frame"

                        width: Math.max(200, (bodyCol.width - 14) / 2)
                        implicitHeight: cardCol.implicitHeight + 28
                        height: implicitHeight
                        radius: Theme.radiusCard
                        color: card.selected
                            ? Qt.tint(Theme.card, Qt.alpha(Theme.accent, 0.12))
                            : (cardHover.hovered ? Theme.hover : Qt.alpha(Theme.t1, 0.03))
                        border.width: card.selected ? 2 : 1
                        border.color: card.selected ? Theme.accent : Theme.rim

                        Behavior on color {
                            ColorAnimation { duration: Theme.motionFast }
                        }
                        Behavior on border.color {
                            ColorAnimation { duration: Theme.motionFast }
                        }

                        Column {
                            id: cardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 10

                            // Miniature schematic wallpaper/bar preview tinted to live Theme palette.
                            Rectangle {
                                id: previewScreen
                                width: parent.width
                                height: 92
                                radius: 10
                                clip: true
                                color: Qt.tint(Theme.card, Qt.alpha(Theme.t2, 0.10))
                                border.width: 1
                                border.color: Theme.rim

                                // Subtle inner wallpaper gradient suggestion
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: Qt.alpha(Theme.accent, 0.10) }
                                        GradientStop { position: 1.0; color: Qt.alpha(Theme.live, 0.05) }
                                    }
                                }

                                // Classic "pills" schematic
                                Item {
                                    anchors.fill: parent
                                    visible: !card.isFrameCard

                                    Row {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.topMargin: 8
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        height: 16

                                        Rectangle {
                                            width: 58; height: 14; radius: 7
                                            color: Theme.popBg; border.width: 1; border.color: Theme.rim
                                            Rectangle {
                                                x: 4; y: 4; width: 14; height: 6; radius: 3; color: Theme.accent
                                            }
                                            Rectangle {
                                                x: 22; y: 5; width: 10; height: 4; radius: 2; color: Theme.t3
                                            }
                                        }
                                        Item { width: Math.max(8, parent.width - 58 - 44 - 52); height: 1 }
                                        Rectangle {
                                            width: 44; height: 14; radius: 7
                                            color: Theme.popBg; border.width: 1; border.color: Theme.rim
                                            Rectangle {
                                                anchors.centerIn: parent; width: 22; height: 4; radius: 2; color: Theme.t2
                                            }
                                        }
                                        Item { width: 4; height: 1 }
                                        Rectangle {
                                            width: 48; height: 14; radius: 7
                                            color: Theme.popBg; border.width: 1; border.color: Theme.rim
                                            Rectangle {
                                                anchors.centerIn: parent; width: 24; height: 4; radius: 2; color: Theme.t2
                                            }
                                        }
                                    }

                                    // Floating popup card preview
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 28
                                        width: 82
                                        height: 44
                                        radius: 9
                                        color: Theme.popBg
                                        border.width: 1
                                        border.color: Theme.rim

                                        Rectangle {
                                            x: 8; y: 9; width: 32; height: 4; radius: 2; color: Theme.accent
                                        }
                                        Rectangle {
                                            x: 8; y: 18; width: 64; height: 4; radius: 2; color: Theme.t2
                                        }
                                        Rectangle {
                                            x: 8; y: 27; width: 46; height: 4; radius: 2; color: Theme.t3
                                        }
                                    }
                                }

                                // "frame" schematic
                                Item {
                                    anchors.fill: parent
                                    visible: card.isFrameCard

                                    // Outer frame borders
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        height: 18
                                        color: Theme.popBg
                                    }
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 6
                                        color: Theme.popBg
                                    }
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 6
                                        color: Theme.popBg
                                    }
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 6
                                        color: Theme.popBg
                                    }

                                    // Subtle inward shadow hint inside preview cutout
                                    Rectangle {
                                        visible: Looks.frameDepth !== "off"
                                        anchors.fill: parent
                                        anchors.topMargin: 18
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        anchors.bottomMargin: 6
                                        radius: 9
                                        color: "transparent"
                                        border.width: Looks.frameDepth === "medium" ? 4 : 2
                                        border.color: Qt.alpha("#000000", Looks.frameDepth === "medium" ? 0.45 : 0.28)
                                    }

                                    // Inner rounded cutout line
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.topMargin: 18
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        anchors.bottomMargin: 6
                                        radius: 9
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Theme.rim
                                    }

                                    // Flat bar indicators in top lip
                                    Rectangle {
                                        x: 12; y: 6; width: 16; height: 6; radius: 3; color: Theme.accent
                                    }
                                    Rectangle {
                                        x: 32; y: 7; width: 10; height: 4; radius: 2; color: Theme.t3
                                    }
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 7; width: 28; height: 4; radius: 2; color: Theme.t1
                                    }
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        y: 7; width: 22; height: 4; radius: 2; color: Theme.t2
                                    }

                                    // Attached morphing drawer preview hanging from top lip
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 17
                                        width: 86
                                        height: 46
                                        topLeftRadius: 0
                                        topRightRadius: 0
                                        bottomLeftRadius: 10
                                        bottomRightRadius: 10
                                        color: Theme.popBg
                                        border.width: 1
                                        border.color: Theme.rim

                                        Rectangle {
                                            x: 1; y: 0; width: parent.width - 2; height: 2; color: Theme.card
                                        }
                                        Rectangle {
                                            x: 8; y: 9; width: 34; height: 4; radius: 2; color: Theme.accent
                                        }
                                        Rectangle {
                                            x: 8; y: 19; width: 66; height: 4; radius: 2; color: Theme.t2
                                        }
                                        Rectangle {
                                            x: 8; y: 29; width: 48; height: 4; radius: 2; color: Theme.t3
                                        }
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: 8

                                Text {
                                    textFormat: Text.PlainText
                                    text: card.modelData.label
                                    color: Theme.t1
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                    font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Rectangle {
                                    visible: card.selected
                                    implicitWidth: activeLabel.implicitWidth + 14
                                    implicitHeight: 20
                                    radius: 10
                                    color: Theme.accent
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        id: activeLabel
                                        textFormat: Text.PlainText
                                        anchors.centerIn: parent
                                        text: "Active"
                                        color: Theme.accentInk
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }
                            }

                            Text {
                                textFormat: Text.PlainText
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: card.modelData.summary
                                color: Theme.t2
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                        }

                        HoverHandler {
                            id: cardHover
                        }

                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: BarConfig.setLook(card.modelData.id)
                        }
                    }
                }
            }

            // ── Frame Customization (only visible when "frame" is active) ──────
            Column {
                width: parent.width
                spacing: 12
                visible: Looks.isFramed

                Text {
                    textFormat: Text.PlainText
                    text: "Frame geometry & feel"
                    color: Theme.t1
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.bold: true
                }

                // Row 1: Frame thickness + Corner rounding sliders
                Row {
                    width: parent.width
                    spacing: 14

                    Rectangle {
                        width: Math.max(200, (bodyCol.width - 14) / 2)
                        implicitHeight: thickCol.implicitHeight + 24
                        height: implicitHeight
                        radius: Theme.radiusCard
                        color: Qt.alpha(Theme.t1, 0.035)
                        border.width: 1
                        border.color: Theme.rim

                        Column {
                            id: thickCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            Row {
                                width: parent.width

                                Text {
                                    textFormat: Text.PlainText
                                    text: "Border thickness"
                                    color: Theme.t1
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.bold: true
                                    width: parent.width - thickVal.implicitWidth
                                }

                                Text {
                                    id: thickVal
                                    textFormat: Text.PlainText
                                    text: Math.round(thickSlider.shownValue) + " px"
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.bold: true
                                }
                            }

                            SettingsSlider {
                                id: thickSlider
                                from: 4
                                to: 14
                                stepSize: 1
                                value: Looks.frameThickness
                                onCommitted: (v) => BarConfig.setLookOption("frameThickness", Math.round(v))
                            }

                            Text {
                                textFormat: Text.PlainText
                                text: "Width of the left, right, and bottom monitor border lips."
                                color: Theme.t3
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                width: parent.width
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    Rectangle {
                        width: Math.max(200, (bodyCol.width - 14) / 2)
                        implicitHeight: roundCol.implicitHeight + 24
                        height: implicitHeight
                        radius: Theme.radiusCard
                        color: Qt.alpha(Theme.t1, 0.035)
                        border.width: 1
                        border.color: Theme.rim

                        Column {
                            id: roundCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            Row {
                                width: parent.width

                                Text {
                                    textFormat: Text.PlainText
                                    text: "Corner rounding"
                                    color: Theme.t1
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.bold: true
                                    width: parent.width - roundVal.implicitWidth
                                }

                                Text {
                                    id: roundVal
                                    textFormat: Text.PlainText
                                    text: Math.round(roundSlider.shownValue) + " px"
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                }
                            }

                            SettingsSlider {
                                id: roundSlider
                                from: 8
                                to: 28
                                stepSize: 1
                                value: Looks.innerRounding
                                onCommitted: (v) => BarConfig.setLookOption("innerRounding", Math.round(v))
                            }

                            Text {
                                textFormat: Text.PlainText
                                text: "Radius of the screen's inner corners. Drawer and card corners follow it up to 20 px."
                                color: Theme.t3
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                width: parent.width
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // Row 2: Surface finish + Motion feel
                Row {
                    width: parent.width
                    spacing: 14

                    Rectangle {
                        width: Math.max(200, (bodyCol.width - 14) / 2)
                        implicitHeight: finishCol.implicitHeight + 24
                        height: implicitHeight
                        radius: Theme.radiusCard
                        color: Qt.alpha(Theme.t1, 0.035)
                        border.width: 1
                        border.color: Theme.rim

                        Column {
                            id: finishCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            Text {
                                textFormat: Text.PlainText
                                text: "Surface finish"
                                color: Theme.t1
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            Row {
                                spacing: 8

                                Chip {
                                    text: "Translucent 92%"
                                    selected: !Looks.solidSurface
                                    onClicked: BarConfig.setLookOption("surfaceFinish", "translucent")
                                }

                                Chip {
                                    text: "Solid Ink"
                                    selected: Looks.solidSurface
                                    onClicked: BarConfig.setLookOption("surfaceFinish", "solid")
                                }
                            }

                            Text {
                                textFormat: Text.PlainText
                                text: "Both finishes keep the crisp 1px inner hairline rim."
                                color: Theme.t3
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                width: parent.width
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    Rectangle {
                        width: Math.max(200, (bodyCol.width - 14) / 2)
                        implicitHeight: motionCol.implicitHeight + 24
                        height: implicitHeight
                        radius: Theme.radiusCard
                        color: Qt.alpha(Theme.t1, 0.035)
                        border.width: 1
                        border.color: Theme.rim

                        Column {
                            id: motionCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            Text {
                                textFormat: Text.PlainText
                                text: "Motion feel"
                                color: Theme.t1
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            Row {
                                spacing: 8

                                Chip {
                                    text: "Expressive"
                                    selected: !Looks.calmMotion
                                    onClicked: BarConfig.setLookOption("motionProfile", "expressive")
                                }

                                Chip {
                                    text: "Calm"
                                    selected: Looks.calmMotion
                                    onClicked: BarConfig.setLookOption("motionProfile", "calm")
                                }
                            }

                            Text {
                                textFormat: Text.PlainText
                                text: "Expressive adds slight spatial bounce on sliding drawers and chips."
                                color: Theme.t3
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                width: parent.width
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // Row 3: Frame depth (inward cutout drop shadow)
                Rectangle {
                    width: parent.width
                    implicitHeight: depthCol.implicitHeight + 24
                    height: implicitHeight
                    radius: Theme.radiusCard
                    color: Qt.alpha(Theme.t1, 0.035)
                    border.width: 1
                    border.color: Theme.rim

                    Column {
                        id: depthCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        Text {
                            textFormat: Text.PlainText
                            text: "Frame depth"
                            color: Theme.t1
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }

                        Row {
                            spacing: 8

                            Chip {
                                text: "Off"
                                selected: Looks.frameDepth === "off"
                                onClicked: BarConfig.setLookOption("frameDepth", "off")
                            }

                            Chip {
                                text: "Subtle"
                                selected: Looks.frameDepth === "subtle"
                                onClicked: BarConfig.setLookOption("frameDepth", "subtle")
                            }

                            Chip {
                                text: "Medium"
                                selected: Looks.frameDepth === "medium"
                                onClicked: BarConfig.setLookOption("frameDepth", "medium")
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "Soft inward shadow cast by the frame, drawers, launcher, and docked OSD over the viewport."
                            color: Theme.t3
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            width: parent.width
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                text: "IPC: quickshell ipc -c tern-bar call bar cycleLook · quickshell ipc -c tern-bar call settings look"
                color: Theme.t3
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
        }
    }
}
