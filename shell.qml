import QtQuick
import Quickshell
import "singletons"

ShellRoot {
    Variants {
        model: Quickshell.screens

        delegate: Component {
            BarPanel {}
        }
    }

    // One floating pet, on the output the engine's settings name (layer surfaces
    // cannot be dragged across outputs, so "Move to next screen" writes the
    // setting instead of moving the window).
    Loader {
        active: !!(Poke.status && Poke.status.pet && Poke.status.pet.enabled)
        sourceComponent: Component {
            PokePet {}
        }
    }
}
