#!/bin/bash
# Copies current MPRIS album art to a fixed path for hyprlock to read
# Also updates the lock screen background from the current wallpaper
DEST=/tmp/hyprlock-art.jpg

# Update lock background symlink to the currently active wallpaper
WP=$(hyprctl hyprpaper listactive 2>/dev/null | awk '{print $NF}' | head -1)
[[ -f "$WP" ]] && ln -sf "$WP" ~/.config/hypr/lockbg

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
