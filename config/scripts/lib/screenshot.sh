#!/bin/bash
# screenshot.sh — shared capture step for screenshot.sh / screenshot-window.sh.
#
# Source (after paths.sh, lib/notify.sh and lib/settings.sh):
#   capture_region <"X,Y WxH">
#
# grim -> save -> wl-copy -> notify -> echo the saved path. The settings store
# (the settings app's Screenshots & recording panel) picks the folder
# (shot-dir), PNG or JPEG (shot-format), the cursor (shot-cursor) and the
# clipboard copy (shot-clipboard).
# A failing wl-copy still notifies (the file is saved); a failing grim notifies
# an error and returns 1. The path goes to stdout only when a file exists, so
# callers such as Quickshell's RegionSelector never open an action modal on a
# missing file.

capture_region() {
    local region=$1 dir format file body
    local -a grim_args=()
    dir=$(setting_dir shot-dir "$SCREENSHOTS_DIR")
    format=$(valid "$(setting shot-format png)" 'png|jpg' png)
    [[ $format == jpg ]] && grim_args+=(-t jpeg -q 92)
    [[ $(setting shot-cursor 0) == 1 ]] && grim_args+=(-c)
    mkdir -p "$dir"
    file="$dir/$(date +%Y%m%d-%H%M%S).$format"

    if ! grim "${grim_args[@]}" -g "$region" "$file"; then
        notify critical screenshot dialog-error "Screenshot failed" "grim could not capture $region" 3000
        return 1
    fi

    body="Saved to $file"
    if [[ $(setting shot-clipboard 1) == 1 ]]; then
        wl-copy <"$file" || body="Saved to $file (clipboard copy failed)"
    fi
    notify normal screenshot "$file" "Screenshot" "$body" 3000

    echo "$file"
}
