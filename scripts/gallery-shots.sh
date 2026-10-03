#!/bin/bash
# gallery-shots.sh - Retake the README gallery pictures from the live shell.
#
# Usage:
#   gallery-shots.sh              # retake every popup shot
#   gallery-shots.sh sound toast  # retake only the named shots
#   gallery-shots.sh --list       # print the shot names
#
# Switches to an empty workspace so no window shows behind the popups, captures
# a baseline, then opens each popup through its Quickshell global shortcut and
# crops the capture to whatever changed against the baseline (plus a margin).
# The bar is ignored in the comparison because its clock and badges change.
# Restores the workspace you started on when done.
#
# Not covered: bar.png, desktop.png and wallpaper.png (no popup to trigger).
set -euo pipefail

OUT_DIR="$(dirname "${BASH_SOURCE[0]}")/../screenshots/gallery"
BAR_HEIGHT=40
MARGIN=34
SETTLE_SECONDS=1.5
TOAST_SECONDS=1.5

# name:shortcut. "toast" has no shortcut; it fires a notification instead.
SHOTS=(
    spotlight:spotlight
    clipboard:clipboard
    quickactions:quickactions
    network:bluetooth
    sound:audiopower
    power:powermenu
    systemmonitor:sysmon
    services:services
    daypanel:calendar
    keybinds:keybinds
    toast:
)

WORK_DIR=$(mktemp -d)
START_WORKSPACE=""

shot_names() {
    local entry
    for entry in "${SHOTS[@]}"; do echo "${entry%%:*}"; done
}

shortcut_for() {
    local entry
    for entry in "${SHOTS[@]}"; do
        [[ "${entry%%:*}" == "$1" ]] && {
            echo "${entry#*:}"
            return 0
        }
    done
    return 1
}

dispatch() {
    hyprctl dispatch "$1" >/dev/null
}

toggle_shortcut() {
    dispatch "hl.dsp.global(\"quickshell:$1\")"
}

restore_workspace() {
    [[ -n "$START_WORKSPACE" ]] && dispatch "hl.dsp.focus({ workspace = $START_WORKSPACE })"
    rm -rf "$WORK_DIR"
}

# Bounding box "WxH+X+Y" of everything that differs from the baseline below the bar.
changed_box() {
    local full_width
    full_width=$(magick identify -format '%w' "$1")
    magick "$1" "$2" -compose difference -composite \
        -crop "${full_width}x+0+${BAR_HEIGHT}" +repage \
        -fuzz 4% -trim -format '%wx%h%O' info:
}

# Crop capture $1 to box $2 grown by MARGIN, clamped to the screen, into $3.
crop_to_box() {
    local capture=$1 box=$2 out=$3
    local width height x y screen_w screen_h
    IFS='x+' read -r width height x y <<<"$box"
    y=$((y + BAR_HEIGHT))
    read -r screen_w screen_h < <(magick identify -format '%w %h' "$capture")
    local left=$((x - MARGIN)) top=$((y - MARGIN))
    local right=$((x + width + MARGIN)) bottom=$((y + height + MARGIN))
    ((left < 0)) && left=0
    ((top < BAR_HEIGHT)) && top=$BAR_HEIGHT
    ((right > screen_w)) && right=$screen_w
    ((bottom > screen_h)) && bottom=$screen_h
    magick "$capture" -crop "$((right - left))x$((bottom - top))+${left}+${top}" +repage "$out"
}

open_popup() {
    local name=$1 shortcut=$2
    if [[ -n "$shortcut" ]]; then
        toggle_shortcut "$shortcut"
        sleep "$SETTLE_SECONDS"
    else
        notify-send -a "Hyprland dots" "Warm ember applied" \
            "Orange primary, punchier accents across shell, kitty and btop"
        sleep "$TOAST_SECONDS"
    fi
    echo "  opened $name" >&2
}

close_popup() {
    local shortcut=$1
    [[ -n "$shortcut" ]] && toggle_shortcut "$shortcut"
    sleep 0.8
}

take_shot() {
    local name=$1 baseline=$2 shortcut capture box
    shortcut=$(shortcut_for "$name")
    capture="$WORK_DIR/$name.png"
    open_popup "$name" "$shortcut"
    grim "$capture"
    close_popup "$shortcut"
    box=$(changed_box "$capture" "$baseline")
    if [[ -z "$box" || "$box" == 0x0* ]]; then
        echo "  $name: nothing changed against the baseline, skipped" >&2
        return 1
    fi
    crop_to_box "$capture" "$box" "$OUT_DIR/$name.png"
    echo "  wrote screenshots/gallery/$name.png ($(magick identify -format '%wx%h' "$OUT_DIR/$name.png"))" >&2
}

main() {
    if [[ "${1:-}" == "--list" ]]; then
        shot_names
        exit 0
    fi

    local names=("$@") name failed=0
    [[ ${#names[@]} -eq 0 ]] && mapfile -t names < <(shot_names)
    for name in "${names[@]}"; do
        shortcut_for "$name" >/dev/null || {
            echo "unknown shot: $name (try --list)" >&2
            exit 2
        }
    done

    START_WORKSPACE=$(hyprctl activeworkspace -j | jq -r '.id')
    trap restore_workspace EXIT
    dispatch 'hl.dsp.focus({ workspace = "empty" })'
    sleep 1

    local baseline="$WORK_DIR/baseline.png"
    grim "$baseline"
    for name in "${names[@]}"; do
        take_shot "$name" "$baseline" || failed=1
    done
    exit "$failed"
}

main "$@"
