#!/bin/bash

# List your monitor names here (as seen in hyprctl monitors)
# Dynamically detect connected monitor names using hyprctl
MONITORS=($(hyprctl monitors -j | jq -r '.[].name'))
WALLPAPER_DIR="/mnt/DATA/Home_Folders/Pictures/wallpapers"

# Wait for hyprpaper socket to appear (max 10 seconds)
SOCKET=$(find /run/user/$(id -u)/hypr/ -name '*.hyprpaper.sock' 2>/dev/null | head -n 1)
TIMEOUT=10
while [ -z "$SOCKET" ] && [ $TIMEOUT -gt 0 ]; do
    sleep 1
    TIMEOUT=$((TIMEOUT-1))
    SOCKET=$(find /run/user/$(id -u)/hypr/ -name '*.hyprpaper.sock' 2>/dev/null | head -n 1)
done

if [ -z "$SOCKET" ]; then
    echo "Hyprpaper socket not found. Is Hyprpaper running?"
    exit 1
fi

# Pick a single random wallpaper for all monitors
wp=$(find "$WALLPAPER_DIR" -type f | shuf -n 1)
for monitor in "${MONITORS[@]}"; do
    hyprctl hyprpaper wallpaper "$monitor,$wp"
done