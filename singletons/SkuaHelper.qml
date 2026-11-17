pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// skua-helper (tools/skua-helper): the background jobs QML cannot do, in one
// Rust program that each HelperJob runs as a process of its own. This says
// whether it is installed, and which version this copy of the bar expects: the
// one in the Cargo.toml next to it. A helper built before a `git pull` that
// changed it reports an older one, and HelperJob.outdated says so.
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

    FileView {
        id: cargoFile
        path: Quickshell.shellDir + "/tools/skua-helper/Cargo.toml"
        blockLoading: true
        printErrors: false
    }
}
