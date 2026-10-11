import QtQuick
import Quickshell
import Quickshell.Io
import "../singletons"

// CPU and memory sampled every 3s from /proc. CPU is a delta between two
// samples (same math as top); memory is 1 - MemAvailable/MemTotal.
// Reads go through `cat` rather than FileView: FileView.reload() does not
// refresh synchronously, so deltas never moved there.
Row {
    id: root

    property string buffer: ""
    property real lastTotal: 0
    property real lastIdle: 0
    property bool haveBaseline: false
    property int cpuUsage: 0
    property int memUsage: 0

    function parse(text) {
        var nl = text.indexOf("\n");
        var firstLine = nl >= 0 ? text.substr(0, nl) : text;
        if (firstLine.indexOf("cpu ") === 0) {
            var p = firstLine.trim().split(/\s+/);
            var total = Number(p[1]) + Number(p[2]) + Number(p[3]) + Number(p[4])
                      + Number(p[5]) + Number(p[6]) + Number(p[7]) + Number(p[8]);
            var idleAll = Number(p[4]) + Number(p[5]);
            if (root.haveBaseline && total > root.lastTotal) {
                var dTotal = total - root.lastTotal;
                var dIdle = idleAll - root.lastIdle;
                root.cpuUsage = Math.round(100 * (1 - dIdle / dTotal));
            }
            root.lastTotal = total;
            root.lastIdle = idleAll;
            root.haveBaseline = true;
        }

        var totalM = /MemTotal:\s+(\d+)/.exec(text);
        var availM = /MemAvailable:\s+(\d+)/.exec(text);
        if (totalM && availM)
            root.memUsage = Math.round(100 * (1 - Number(availM[1]) / Number(totalM[1])));
    }

    Process {
        id: sampler
        command: ["cat", "/proc/stat", "/proc/meminfo"]
        stdout: SplitParser {
            onRead: (line) => root.buffer += line + "\n"
        }
        onExited: (exitCode, exitStatus) => {
            root.parse(root.buffer);
            root.buffer = "";
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: {
            if (!sampler.running) {
                root.buffer = "";
                sampler.running = true;
            }
        }
    }

    Component.onCompleted: {
        root.buffer = "";
        sampler.running = true;
    }

    BarItem {
        text: "󰍛 " + root.cpuUsage + "%"
        fg: Theme.t2
    }

    BarItem {
        text: "󰘚 " + root.memUsage + "%"
        fg: Theme.t2
    }
}
