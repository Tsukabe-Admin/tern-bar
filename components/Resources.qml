import QtQuick
import "../singletons"

// The CPU and memory pills. The sampling lives in SysStats, shared by every bar.
Row {
    id: root

    BarItem {
        text: "󰍛 " + SysStats.cpuUsage + "%"
        fg: Theme.t2
    }

    BarItem {
        text: "󰘚 " + SysStats.memUsage + "%"
        fg: Theme.t2
    }
}
