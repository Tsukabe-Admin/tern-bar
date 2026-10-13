import QtQuick
import Quickshell.Widgets
import "../singletons"

// One image in the wallpaper grid: the thumbnail, its filename on hover, whether
// it is a favourite, and which screens are currently showing it.
//
// `target` is what a click would set — "*" for All screens, else an output name.
// It is a plain string rather than the page itself: a property named `page` here
// would shadow the page's own id at every use site and make the binding
// self-referential.
Item {
    id: root

    required property string path
    required property string name
    required property string target

    readonly property bool isCurrent: Wallpaper.current(root.target) === root.path
    readonly property var onScreens: Wallpaper.screensShowing(root.path)
    readonly property bool fav: Wallpaper.isFavorite(root.path)

    // Whether the pointer is over the tile. Exposed as a property of the root
    // (the same shape Pill.qml uses) because a bare id reference from a sibling's
    // binding resolves to nothing while the delegate is still being built.
    readonly property bool hovered: hoverHandler.hovered

    HoverHandler {
        id: hoverHandler
    }

    // Everything visible is inset, so the gaps double as breathing room and the
    // tile's own hover area still covers the whole cell.
    Item {
        id: box
        anchors.fill: parent
        anchors.margins: 5

        ClippingRectangle {
            id: thumb
            anchors.fill: parent
            radius: 10
            color: Theme.hover

            Image {
                anchors.fill: parent
                asynchronous: true
                sourceSize.width: 384
                fillMode: Image.PreserveAspectCrop
                source: Wallpaper.fileUrl(root.path)
                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.motionBase
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // Everything stacked above this is decoration that takes no mouse input,
        // so clicks still land here. The star is the exception and comes last.
        MouseArea {
            anchors.fill: parent
            onClicked: Wallpaper.setWallpaper(root.target, root.path)
        }

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: Theme.hover
            opacity: (root.hovered && !root.isCurrent) ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.motionFast
                    easing.type: Easing.OutCubic
                }
            }
        }

        // The filename, on hover only: the picture is the point, the name is
        // what you check before clicking.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 26
            visible: root.hovered
            color: Qt.alpha(Theme.card, 0.8)

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.name
                elide: Text.ElideRight
                color: Theme.t1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }

        // The one this target is showing.
        Rectangle {
            anchors.fill: parent
            radius: 10
            color: "transparent"
            border.width: 2
            border.color: Theme.accent
            visible: root.isCurrent
        }

        Row {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 6
            spacing: 4
            visible: Wallpaper.screens.length > 1 && root.onScreens.length > 0

            Repeater {
                model: root.onScreens

                delegate: Rectangle {
                    required property string modelData
                    width: badge.implicitWidth + 10
                    height: 16
                    radius: height / 2
                    color: Theme.popBg

                    Text {
                        id: badge
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: Theme.t2
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }
            }
        }

        // Last, so a click on the star does not also set the wallpaper.
        Item {
            id: star
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 4
            width: 26
            height: 26
            visible: root.hovered || root.fav

            Text {
                anchors.centerIn: parent
                text: root.fav ? "\u2605" : "\u2606"
                color: root.fav ? Theme.accent : Theme.t1
                font.family: Theme.fontFamily
                font.pixelSize: 16
            }

            MouseArea {
                anchors.fill: parent
                onClicked: Wallpaper.toggleFavorite(root.path)
            }
        }
    }
}
