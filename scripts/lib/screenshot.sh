#!/bin/bash
# screenshot.sh — shared capture step for screenshot.sh / screenshot-window.sh.
#
# Source (after paths.sh and lib/notify.sh):
#   capture_region <"X,Y WxH">
#
# grim -> save to $SCREENSHOTS_DIR -> wl-copy -> notify -> echo the saved path.
# A failing wl-copy still notifies (the file is saved); a failing grim notifies
# an error and returns 1. The path goes to stdout only when a file exists, so
# callers such as Quickshell's RegionSelector never open an action modal on a
# missing file.

capture_region() {
    local region=$1 file body
    mkdir -p "$SCREENSHOTS_DIR"
    file="$SCREENSHOTS_DIR/$(date +%Y%m%d-%H%M%S).png"

    if ! grim -g "$region" "$file"; then
        notify critical screenshot dialog-error "Screenshot failed" "grim could not capture $region" 3000
        return 1
    fi

    body="Saved to $file"
    wl-copy < "$file" || body="Saved to $file (clipboard copy failed)"
    notify normal screenshot "$file" "Screenshot" "$body" 3000

    echo "$file"
}
