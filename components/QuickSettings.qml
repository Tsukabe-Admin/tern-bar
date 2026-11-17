import QtQuick
import "../singletons"
import "views"

// Quick settings popup (Pills look).
PopoutPopupHost {
    id: pop

    alignMode: "right"
    open: Popups.open === "quick" && pop.screenInfo !== null
        && Popups.screenName === pop.screenInfo.name

    QuickSettingsView {
        screenInfo: pop.screenInfo
        active: pop.open
    }
}
