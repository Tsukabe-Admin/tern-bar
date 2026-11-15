import QtQuick
import "../singletons"
import "views"

// Notification centre popup under the bell (Classic Pills look).
PopoutPopupHost {
    id: pop

    alignMode: "right"
    open: Popups.open === "notifications" && pop.screenInfo !== null
        && Popups.screenName === pop.screenInfo.name

    NotificationsView {
        screenInfo: pop.screenInfo
        active: pop.open
    }
}
