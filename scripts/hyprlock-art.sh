#!/bin/bash
# Copies current MPRIS album art to a fixed path for hyprlock to read
# Also updates the lock screen background from the current wallpaper
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
DEST="$LOCK_ART"

# Pick a random wallpaper for the lock background
WP=$(find "$WALLPAPER_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.webp" \) 2>/dev/null | shuf -n1)
[[ -f "$WP" ]] && ln -sf "$WP" "$LOCK_BG"

url=$(playerctl metadata mpris:artUrl 2>/dev/null)

if [[ -z "$url" ]]; then
    rm -f "$DEST"
    exit 0
fi

if [[ "$url" == file://* ]]; then
    cp "${url#file://}" "$DEST"
else
    curl -sf -o "$DEST" "$url"
fi
