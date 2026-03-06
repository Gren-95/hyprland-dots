#!/bin/bash
# powermenu.sh - Rofi power menu

LOCK="$(printf '\uf023')   Lock"
SUSPEND="$(printf '\uf186')  Suspend"
LOGOUT="$(printf '\uf2f5')   Logout"
REBOOT="$(printf '\uf2f9')   Reboot"
SHUTDOWN="$(printf '\uf011')   Shutdown"

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
