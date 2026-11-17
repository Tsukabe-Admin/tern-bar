#!/usr/bin/env bash
# Switch the bar between showing and hiding your IP address.
# The state file exists only while the IP is shown, so hiding is the default.
# The bar watches the file and confirms the change on screen itself.

STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/skua/show_ip"

mkdir -p "$(dirname "$STATE_FILE")"

if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE"
else
    touch "$STATE_FILE"
fi
