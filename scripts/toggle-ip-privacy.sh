#!/usr/bin/env bash
# Switch the bar between showing and hiding your IP address.

STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/tern-bar/hide_ip"

mkdir -p "$(dirname "$STATE_FILE")"

if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE"
    notify-send -a "Privacy Mode" "IP Address Visible" -i network-transmit-receive -t 2000
else
    touch "$STATE_FILE"
    notify-send -a "Privacy Mode" "IP Address Blurred / Hidden" -i security-high -t 2000
fi
