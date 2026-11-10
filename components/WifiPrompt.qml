import QtQuick
import "../singletons"

// The Wi-Fi password, asked when a network that needs one is clicked in quick
// settings, and again when NetworkManager says it did not work (see
// WifiNetworks). One window for the whole shell, under the bar; the window and
// its keyboard rules are PromptWindow's.
PromptWindow {
    id: win

    readonly property var pending: WifiNetworks.pending

    token: win.pending
    open: win.pending !== null
    screenName: win.pending ? win.pending.screenName : ""
    glyph: "\uf1eb"
    title: (win.pending && win.pending.network) ? win.pending.network.name : ""
    message: (win.pending && win.pending.retry)
        ? "That password didn't work. Type it again:" : "Type the Wi-Fi password:"
    typed: true
    secret: true
    // WPA: 8 to 63 printable characters, or the 64-digit hex key itself.
    maxLength: 64
    inputPattern: /[\x20-\x7E]{0,64}/
    accept: (text) => /^.{8,63}$/.test(text) || /^[0-9A-Fa-f]{64}$/.test(text)
    primaryText: "Connect"
    secondaryText: "Cancel"
    layerNamespace: "tern-bar-wifi"

    onPrimary: (text) => WifiNetworks.submit(text)
    onSecondary: WifiNetworks.cancel()
}
