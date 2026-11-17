import QtQuick
import "../singletons"
import "views"

// Month calendar and forecast popup under the clock/weather pills (Pills look).
PopoutPopupHost {
    id: pop

    alignMode: "center"
    open: Popups.open === "calendar" && pop.screenInfo !== null
        && Popups.screenName === pop.screenInfo.name

    CalendarView {
        screenInfo: pop.screenInfo
        active: pop.open
    }
}
