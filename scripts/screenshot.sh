#!/bin/bash
# screenshot.sh - Take a screenshot, save to file and copy to clipboard
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

mkdir -p "$SCREENSHOTS_DIR"
FILE="$SCREENSHOTS_DIR/$(date +%Y%m%d-%H%M%S).png"

REGION=$(slurp -d) || exit 0

grim -g "$REGION" "$FILE" && \
    wl-copy < "$FILE" && \
    notify-send "Screenshot" "Saved to $FILE" -i "$FILE" -t 3000

