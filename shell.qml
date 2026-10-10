import QtQuick
import Quickshell

ShellRoot {
    Variants {
        model: Quickshell.screens

        delegate: Component {
            BarPanel {}
        }
    }
}
