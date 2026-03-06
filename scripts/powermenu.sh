#!/bin/bash
# powermenu.sh - Rofi power menu

LOCK="  Lock"
SUSPEND="  Suspend"
LOGOUT="󰗼  Logout"
REBOOT="  Reboot"
SHUTDOWN="  Shutdown"

CHOSEN=$(printf '%s\n' "$LOCK" "$SUSPEND" "$LOGOUT" "$REBOOT" "$SHUTDOWN" \
    | rofi -dmenu \
        -p "Power" \
        -mesg "$(hostname)  •  $(uptime -p)" \
        -no-custom \
        -theme ~/.config/rofi/powermenu.rasi)

case "$CHOSEN" in
    "$LOCK")     loginctl lock-session ;;
    "$SUSPEND")  systemctl suspend ;;
    "$LOGOUT")   hyprctl dispatch exit ;;
    "$REBOOT")   systemctl reboot ;;
    "$SHUTDOWN")  systemctl poweroff ;;
esac
