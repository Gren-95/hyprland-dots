#!/bin/bash
set -euo pipefail

# List your monitor names here (as seen in hyprctl monitors)
# Dynamically detect connected monitor names using hyprctl
MONITORS=($(hyprctl monitors -j | jq -r '.[].name'))
WALLPAPER_DIR="$HOME/Pictures/wallpapers"

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

# If a path is given as $1, apply that exact wallpaper. Otherwise pick a
# random one from $WALLPAPER_DIR. The file must already be preloaded by
# hyprpaper (restart.sh generates the preload list for everything in the
# wallpapers directory at startup).
if [[ $# -ge 1 && -f "$1" ]]; then
    wp="$1"
else
    wp=$(find "$WALLPAPER_DIR" -type f | shuf -n 1)
fi

for monitor in "${MONITORS[@]}"; do
    hyprctl hyprpaper wallpaper "$monitor,$wp"
done

echo "Wallpaper set: $wp"