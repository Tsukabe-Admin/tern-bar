#!/usr/bin/env bash
# Power menu using fuzzel

OPTIONS="  Lock\n󰤄  Suspend\n󰍃  Logout\n󰜉  Reboot\n  Power Off"

CHOSEN=$(echo -e "$OPTIONS" | fuzzel --dmenu --prompt="⏻ Power: " --lines=5 --width=22)

case "$CHOSEN" in
    *"Lock"*)
        swaylock -f -c 1e1e2e
        ;;
    *"Suspend"*)
        swaylock -f -c 1e1e2e && systemctl suspend
        ;;
    *"Logout"*)
        niri msg action quit --skip-confirmation
        ;;
    *"Reboot"*)
        systemctl reboot
        ;;
    *"Power Off"*)
        systemctl poweroff
        ;;
esac
