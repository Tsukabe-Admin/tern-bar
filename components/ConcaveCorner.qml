import QtQuick
import QtQuick.Shapes
import "../singletons"

// Pure-QML concave ("inverted") corner wedge using QtQuick.Shapes CurveRenderer.
// Fills the corner bracket cleanly against an inner cutout of `radius`, and draws
// a 1px inner hairline arc whose ends align on 0.5px pixel centers with straight
// adjacent border hairlines (zero T-junctions and zero double-alpha overlap).
//
// `corner` values: "topLeft" | "topRight" | "bottomLeft" | "bottomRight".
Item {
    id: root

    property string corner: "topLeft"
    property real radius: Theme.innerRounding
    property color fillColor: Theme.popBg
    property color strokeColor: Theme.rim
    property real strokeWidth: 1

    readonly property real r: Math.max(0, root.radius)
    readonly property real o: root.strokeWidth * 0.5
    readonly property real sr: root.r + root.o

    implicitWidth: root.r
    implicitHeight: root.r
    width: root.r
    height: root.r
    visible: root.r > 0.5

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true
        smooth: true

        // 1. Solid/translucent corner wedge fill (zero stroke on straight joins).
        ShapePath {
            fillColor: root.fillColor
            strokeColor: "transparent"
            strokeWidth: 0

            startX: (root.corner === "topRight" || root.corner === "bottomRight") ? root.r : 0
            startY: (root.corner === "bottomLeft" || root.corner === "bottomRight") ? root.r : 0

            PathLine {
                x: (root.corner === "topLeft" || root.corner === "bottomRight") ? root.r : 0
                y: 0
            }

            PathArc {
                x: (root.corner === "topRight" || root.corner === "bottomLeft") ? root.r : 0
                y: root.r
                radiusX: root.r
                radiusY: root.r
                useLargeArc: false
                direction: (root.corner === "topRight" || root.corner === "bottomRight")
                    ? PathArc.Clockwise
                    : PathArc.Counterclockwise
            }

            PathLine {
                x: root.corner === "topRight" ? root.r : (root.corner === "bottomRight" ? root.r : 0)
                y: (root.corner === "bottomLeft" || root.corner === "bottomRight") ? root.r : 0
            }
        }

        // 2. 1px curved inner hairline only (straight legs stay stroke-free).
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.strokeWidth > 0 ? root.strokeColor : "transparent"
            strokeWidth: root.strokeWidth
            capStyle: ShapePath.FlatCap

            startX: root.corner === "topLeft" ? root.r
                  : root.corner === "topRight" ? 0
                  : root.corner === "bottomLeft" ? -root.o
                  : (root.r + root.o)
            startY: root.corner === "topLeft" ? -root.o
                  : root.corner === "topRight" ? -root.o
                  : 0

            PathArc {
                x: root.corner === "topLeft" ? -root.o
                 : root.corner === "topRight" ? (root.r + root.o)
                 : root.corner === "bottomLeft" ? root.r
                 : 0
                y: root.corner === "topLeft" ? root.r
                 : root.corner === "topRight" ? root.r
                 : (root.r + root.o)
                radiusX: root.sr
                radiusY: root.sr
                useLargeArc: false
                direction: (root.corner === "topRight" || root.corner === "bottomRight")
                    ? PathArc.Clockwise
                    : PathArc.Counterclockwise
            }
        }
    }
}
