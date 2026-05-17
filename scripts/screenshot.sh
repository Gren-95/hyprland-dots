#!/bin/bash
# screenshot.sh - Take a screenshot, save to file and copy to clipboard
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"

mkdir -p "$SCREENSHOTS_DIR"
FILE="$SCREENSHOTS_DIR/$(date +%Y%m%d-%H%M%S).png"

REGION=$(slurp -d) || exit 0

grim -g "$REGION" "$FILE" && \
    wl-copy < "$FILE" && \
    notify normal screenshot "$FILE" "Screenshot" "Saved to $FILE" 3000

