import QtQuick
import "../singletons"

// One view of the Frame look's drawer (FrameHost). The drawer shows one view
// at a time and morphs from one to the next; during that morph the view being
// left stays loaded for one fade, under the one coming in, so the two
// cross-fade rather than the old one vanishing at once.
Loader {
    id: slot

    // Which popup this is: "calendar", "quick", ...
    required property string kind
    // The FrameHost: its displayKind, fadingKind, drawerVis and trackMorph.
    required property var host

    readonly property bool current: slot.host.displayKind === slot.kind

    active: slot.host.drawerVis && (slot.current || slot.host.fadingKind === slot.kind)
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    opacity: slot.current && slot.item ? 1 : 0
    // The view on its way out takes no clicks and lies under the new one.
    enabled: slot.current
    z: slot.current ? 1 : 0

    // Only between two drawers. A drawer opening from the lip fades in as a
    // whole (FrameHost's drawerScroll), and one fade is enough.
    Behavior on opacity {
        enabled: !Looks.restyling && slot.host.trackMorph
        NumberAnimation {
            duration: Theme.motionFast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveEffects
        }
    }
}
