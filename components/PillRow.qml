import QtQuick
import "../singletons"

// A bar row that knows when it is crowded. At Theme.pillMergeThreshold visible
// capsules its children stop drawing their own fill and one GroupBackground
// behind the row draws a single island; the spacing closes so the row reads as
// one continuous capsule. Below the threshold it is an ordinary Row.
Row {
    id: rowRoot

    property int visiblePills: 0
    readonly property bool merged: visiblePills >= Theme.pillMergeThreshold

    function recount() {
        let n = 0;
        for (let i = 0; i < children.length; i++) {
            if (children[i].visible)
                n++;
        }
        visiblePills = n;
    }

    spacing: merged ? 0 : Theme.pillSpacing
    Behavior on spacing {
        NumberAnimation { duration: Theme.motionSlow; easing.type: Easing.OutCubic }
    }

    onChildrenChanged: recount()
    Component.onCompleted: recount()
}
