#!/bin/bash
# Toggle waybar between floating and docked mode

FLOATING="$HOME/.config/waybar/config"
DOCKED="$HOME/.config/waybar/config-docked"
ACTIVE="$HOME/.config/waybar/config-active"

# Determine current mode from symlink or fallback to floating
if [[ -L "$ACTIVE" ]] && [[ "$(readlink "$ACTIVE")" == "$DOCKED" ]]; then
    ln -sf "$FLOATING" "$ACTIVE"
    notify-send -i preferences-desktop "Waybar" "Switched to floating mode"
else
    ln -sf "$DOCKED" "$ACTIVE"
    notify-send -i preferences-desktop "Waybar" "Switched to docked mode"
fi

killall waybar
waybar -c "$ACTIVE" &
