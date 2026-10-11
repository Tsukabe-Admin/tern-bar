#!/usr/bin/env bash
# Network status for tern-bar, with an option to hide your IP address.
# Prints one line of JSON: {"text", "tooltip", "class"}.

STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/tern-bar/hide_ip"

# Escape a value for a JSON string literal.
json_escape() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    printf '%s' "$s"
}

# Get the interface used by the default route.
IFACE=$(ip route show default 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')

if [ -z "$IFACE" ]; then
    echo '{"text": "󰤮  Offline", "tooltip": "No network connection", "class": "disconnected"}'
    exit 0
fi

# Get IPv4 address
IP=$(ip -4 addr show "$IFACE" 2>/dev/null | awk '/inet /{split($2, a, "/"); print a[1]; exit}')
[ -z "$IP" ] && IP="No IP"

# Wireless vs wired
if [ -d "/sys/class/net/$IFACE/wireless" ]; then
    SSID=$(iwgetid -r 2>/dev/null || true)
    [ -z "$SSID" ] && SSID=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '/^yes:/{print $2; exit}')
    [ -z "$SSID" ] && SSID="$IFACE"

    if [ -f "$STATE_FILE" ]; then
        TEXT="󰤨  ${SSID}"
        TOOLTIP="Interface: ${IFACE}
SSID: ${SSID}
IP: [Hidden for Privacy]
(Click to reveal IP)"
        CLASS="wifi privacy"
    else
        TEXT="󰤨  ${SSID} (${IP})"
        TOOLTIP="Interface: ${IFACE}
SSID: ${SSID}
IP: ${IP}
(Click to hide IP)"
        CLASS="wifi"
    fi
else
    # Ethernet
    if [ -f "$STATE_FILE" ]; then
        TEXT="󰈀  • • • • • •"
        TOOLTIP="Interface: ${IFACE}
IP: [Hidden for Privacy]
(Click to reveal IP)"
        CLASS="ethernet privacy"
    else
        TEXT="󰈀  ${IP}"
        TOOLTIP="Interface: ${IFACE}
IP: ${IP}
(Click to hide IP)"
        CLASS="ethernet"
    fi
fi

printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' \
    "$(json_escape "$TEXT")" "$(json_escape "$TOOLTIP")" "$(json_escape "$CLASS")"
