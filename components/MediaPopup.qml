import QtQuick
import "../singletons"
import "views"

// Expanded MPRIS media player popup (Classic Pills look).
PopoutPopupHost {
    id: pop

    alignMode: "center"
    open: Popups.open === "media" && pop.screenInfo !== null
        && Popups.screenName === pop.screenInfo.name && mediaView.player !== null

    MediaView {
        id: mediaView
        screenInfo: pop.screenInfo
        active: pop.open
    }
}
