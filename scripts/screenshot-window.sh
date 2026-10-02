#!/bin/bash
# screenshot-window.sh - Screenshot the active window; save, copy, notify.
# Same behavior as screenshot.sh, with the region taken from Hyprland.
#
# Usage: screenshot-window.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/screenshot.sh"

REGION=$(hyprctl activewindow -j 2>/dev/null |
    jq -r 'select(.address != null) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"') || REGION=""

if [[ -z "$REGION" ]]; then
    notify normal screenshot dialog-warning "Screenshot" "No active window to capture" 3000
    exit 1
fi

capture_region "$REGION"
