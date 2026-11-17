import QtQuick
import Quickshell
import Quickshell.Io

// One job of skua-helper (`skua-helper <name>`), run as a process of its own
// for as long as `wanted` is true and the program is installed. Each line it
// writes is one JSON object: the first, {"event":"hello", "version": ...}, is
// read here; every other one arrives as received(message). A list inside a
// message reaches the handler as a Qt sequence, not a JS array (Array.isArray
// is false): copy it with Array.from before using array methods. send(message)
// writes one line to it. Quickshell ends the process (SIGTERM) when `wanted`
// turns false or the bar reloads, which ends the job.
//
// A job that stops on its own is started again after 5 s, then 30 s, then every
// 5 minutes, never in a loop; a minute of running resets that.
Scope {
    id: job

    required property string name
    property bool wanted: true

    readonly property bool installed: SkuaHelper.installed
    readonly property bool running: proc.running
    // What the running job said in its hello line; "" before that.
    property string version: ""
    // Built from older sources than this copy of the bar: a `git pull` without
    // a reinstall. The job may still run; whoever shows it should say so.
    readonly property bool outdated: SkuaHelper.outdated || (job.version !== ""
        && SkuaHelper.expectedVersion !== "" && job.version !== SkuaHelper.expectedVersion)
    // Starts that have failed since it last ran for a minute.
    property int failures: 0
    // Stopped on purpose and not ended yet: when it ends that is no failure,
    // and if it is wanted again by then it starts again at once.
    property bool stopping: false

    signal received(var message)
    // The process ended: whatever it was doing has stopped.
    signal stopped

    function send(message) {
        if (proc.running)
            proc.write(JSON.stringify(message) + "\n");
    }

    function start() {
        if (!job.wanted || !job.installed || proc.running || job.stopping)
            return;
        SkuaHelper.recheck();
        proc.running = true;
        startCheck.restart();
    }

    function retry() {
        const delays = [5000, 30000, 300000];
        restartTimer.interval = delays[Math.min(job.failures, delays.length - 1)];
        job.failures++;
        restartTimer.restart();
    }

    onWantedChanged: {
        if (job.wanted) {
            job.failures = 0;
            job.start();
        } else {
            restartTimer.stop();
            startCheck.stop();
            if (proc.running) {
                job.stopping = true;
                proc.running = false;
            }
        }
    }
    onInstalledChanged: job.start()
    Component.onCompleted: job.start()

    Timer {
        id: restartTimer
        onTriggered: job.start()
    }

    // A program that cannot start at all sends no signal; this notices.
    Timer {
        id: startCheck
        interval: 3000
        onTriggered: {
            if (job.wanted && !proc.running && !restartTimer.running)
                job.retry();
        }
    }

    Timer {
        id: healthy
        interval: 60000
        onTriggered: job.failures = 0
    }

    Process {
        id: proc
        command: [SkuaHelper.program, job.name]
        stdinEnabled: true

        stdout: SplitParser {
            onRead: (line) => {
                let message = null;
                try {
                    message = JSON.parse(line);
                } catch (e) {
                    console.warn("skua-helper " + job.name + " wrote a line that is not JSON:", line);
                    return;
                }
                if (!message || typeof message !== "object")
                    return;
                if (message.event === "hello") {
                    job.version = String(message.version || "");
                    healthy.restart();
                    return;
                }
                job.received(message);
            }
        }

        // Only a crash writes here.
        stderr: SplitParser {
            onRead: (line) => console.warn("skua-helper " + job.name + ":", line)
        }

        onRunningChanged: {
            if (proc.running)
                return;
            const deliberate = job.stopping;
            job.stopping = false;
            job.version = "";
            healthy.stop();
            job.stopped();
            if (!job.wanted)
                return;
            if (deliberate)
                job.start();
            else
                job.retry();
        }
    }
}
