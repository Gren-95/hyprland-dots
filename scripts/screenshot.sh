#!/bin/bash
# screenshot.sh - Take a screenshot, save to file and copy to clipboard.
#
# Usage:
#   screenshot.sh                  # slurp region picker (fallback)
#   screenshot.sh "X,Y WxH"        # pre-computed region (from RegionSelector)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"

mkdir -p "$SCREENSHOTS_DIR"
FILE="$SCREENSHOTS_DIR/$(date +%Y%m%d-%H%M%S).png"

if [[ $# -ge 1 && -n "$1" ]]; then
    REGION="$1"
else
    REGION=$(slurp -d) || exit 0
fi

grim -g "$REGION" "$FILE" && \
    wl-copy < "$FILE" && \
    notify normal screenshot "$FILE" "Screenshot" "Saved to $FILE" 3000

# Emit the saved path on stdout so callers (e.g. Quickshell RegionSelector)
# can hand the file to a follow-up action modal — but only if grim actually
# produced a file. Otherwise the action modal would open on a non-existent
# path and OCR/edit/reveal would fail silently.
[[ -f "$FILE" ]] && echo "$FILE"

