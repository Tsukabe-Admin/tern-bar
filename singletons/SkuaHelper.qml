pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// skua-helper (tools/skua-helper): the background jobs QML cannot do, in one
// Rust program that each HelperJob runs as a process of its own. This says
// whether it is installed, which version this copy of the bar expects (the one
// in the Cargo.toml next to it), and which version is installed: a helper built
// before a `git pull` that changed it is outdated.
Singleton {
    id: root

    readonly property string program: "skua-helper"
    readonly property bool installed: Programs.has(root.program)
    // Run from the repository's top folder; the README's Bluetooth section explains.
    readonly property string installCommand: "cargo install --path tools/skua-helper --root ~/.local"

    // [package] version = "x.y.z", or "" when the file cannot be read.
    readonly property string expectedVersion: {
        const m = /^\[package\][^\[]*?^version\s*=\s*"([^"]+)"/m.exec(cargoFile.text());
        return m ? m[1] : "";
    }

    // `skua-helper --version`, asked at start and again before each job starts,
    // so a reinstall while the bar runs is noticed. A job's own hello line cannot
    // be relied on here: a helper too old to have a job prints its usage for it
    // and ends without one. "" while unknown.
    property string installedVersion: ""
    readonly property bool outdated: root.installedVersion !== "" && root.expectedVersion !== ""
        && root.installedVersion !== root.expectedVersion

    function recheck() {
        if (root.installed && !versionCheck.running)
            versionCheck.running = true;
    }

    onInstalledChanged: root.recheck()
    Component.onCompleted: root.recheck()

    Process {
        id: versionCheck
        command: [root.program, "--version"]
        stdout: StdioCollector {
            id: versionText
        }
        onExited: (exitCode, exitStatus) => {
            const m = /^skua-helper\s+(\S+)/.exec(versionText.text.trim());
            root.installedVersion = (exitCode === 0 && m) ? m[1] : "";
        }
    }

    FileView {
        id: cargoFile
        path: Quickshell.shellDir + "/tools/skua-helper/Cargo.toml"
        blockLoading: true
        printErrors: false
    }
}
