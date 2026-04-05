#!/bin/bash
# Copies current MPRIS album art to a fixed path for hyprlock to read
DEST=/tmp/hyprlock-art.jpg

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
