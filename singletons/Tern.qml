pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Polls `tern ls --json` every 2s and counts blocks with live === true.
// `tern` prints pretty-printed multi-line JSON, so stdout lines are
// accumulated and parsed once the process exits.
Singleton {
    id: root

    property bool available: false
    property int liveBlocks: 0
    property string buffer: ""

    function open() {
        Quickshell.execDetached(["/home/tsu/.local/bin/tern"]);
    }

    function parseOutput(exitCode) {
        if (exitCode !== 0) {
            root.available = false;
            return;
        }
        var obj;
        try {
            obj = JSON.parse(root.buffer);
        } catch (e) {
            return; // keep last known state
        }
        var count = 0;
        var sessions = obj.sessions || [];
        for (var i = 0; i < sessions.length; i++) {
            var tabs = sessions[i].tabs || [];
            for (var j = 0; j < tabs.length; j++) {
                var blocks = tabs[j].blocks || [];
                for (var k = 0; k < blocks.length; k++) {
                    if (blocks[k].live === true)
                        count++;
                }
            }
        }
        root.available = true;
        root.liveBlocks = count;
    }

    Process {
        id: poll
        command: ["/home/tsu/.local/bin/tern", "ls", "--json"]
        stdout: SplitParser {
            onRead: (line) => root.buffer += line
        }
        onExited: (exitCode, exitStatus) => root.parseOutput(exitCode)
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: {
            if (!poll.running) {
                root.buffer = "";
                poll.running = true;
            }
        }
    }

    Component.onCompleted: {
        root.buffer = "";
        poll.running = true;
    }
}
