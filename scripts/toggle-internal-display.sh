#!/bin/bash

# Check if eDP-1 is currently enabled
if hyprctl monitors | grep -q "eDP-1"; then
    # Monitor is enabled, disable it
    hyprctl keyword monitor "eDP-1, disable"
    notify-send "Internal Display" "Disabled" -i display
else
    # Monitor is disabled, enable it with preferred settings
    hyprctl keyword monitor "eDP-1, preferred, 0x0, 1"
    notify-send "Internal Display" "Enabled" -i display
fi 