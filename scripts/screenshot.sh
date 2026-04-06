#!/bin/bash
# screenshot.sh - Take a screenshot, save to file and copy to clipboard

SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SCREENSHOT_DIR"
FILE="$SCREENSHOT_DIR/$(date +%Y%m%d-%H%M%S).png"

REGION=$(slurp -d) || exit 0

grim -g "$REGION" "$FILE" && \
    wl-copy < "$FILE" && \
    notify-send "Screenshot" "Saved to $FILE" -i "$FILE" -t 3000
