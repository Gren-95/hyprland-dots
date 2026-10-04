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
# Personal content is swapped out while a shot is taken and put back after:
# the clipboard history is replaced with demo entries, and Bluetooth device
# names lose their "<Owner>'s " prefix.
#
# Not covered: desktop.png (a composed scene with real windows), bar.png (the
# bell badge counts every test toast) and wallpaper.png (the deck only deals
# while Super is held).
set -euo pipefail

OUT_DIR="$(dirname "${BASH_SOURCE[0]}")/../../screenshots/gallery"
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
DEMO_CLIPBOARD=(
    "git switch -c feature/rounded-corners"
    "https://example.com/docs/getting-started"
    "Meeting notes: ship the new theme on Friday"
    "sudo dnf upgrade --refresh"
    "#ff7a1a"
    "SELECT id, email FROM users WHERE active = true;"
    "ssh deploy@staging.example.com"
    "Remember to rebase before opening the PR"
)

WORK_DIR=$(mktemp -d)
START_WORKSPACE=""

shot_names() {
    local entry
    for entry in "${SHOTS[@]}"; do echo "${entry%%:*}"; done
}

# Prints the shortcut for a shot name (empty for toast); fails on unknown names.
shortcut_for() {
    local entry
    for entry in "${SHOTS[@]}"; do
        [[ "${entry%%:*}" == "$1" ]] || continue
        echo "${entry#*:}"
        return 0
    done
    return 1
}

CLIPHIST_DB="$HOME/.cache/cliphist/db"

prep_clipboard() {
    cp "$CLIPHIST_DB" "$WORK_DIR/cliphist.db"
    cliphist wipe
    local entry
    for entry in "${DEMO_CLIPBOARD[@]}"; do
        printf '%s' "$entry" | cliphist store
    done
}

restore_clipboard() {
    if [[ -f "$WORK_DIR/cliphist.db" ]]; then
        cp "$WORK_DIR/cliphist.db" "$CLIPHIST_DB"
    fi
}

bluez_path() {
    echo "/org/bluez/hci0/dev_${1//:/_}"
}

# Writes "<mac>\t<alias>" lines for every paired device to $1.
save_bluetooth_aliases() {
    local mac
    : >"$1"
    while read -r mac; do
        printf '%s\t%s\n' "$mac" \
            "$(busctl -j get-property org.bluez "$(bluez_path "$mac")" org.bluez.Device1 Alias | jq -r .data)" >>"$1"
    done < <(bluetoothctl devices | awk '{print $2}')
}

prep_network() {
    save_bluetooth_aliases "$WORK_DIR/bt-aliases.tsv"
    local mac alias possessive="^.*['’]s "
    while IFS=$'\t' read -r mac alias; do
        [[ "$alias" =~ $possessive ]] || continue
        busctl set-property org.bluez "$(bluez_path "$mac")" org.bluez.Device1 Alias s \
            "$(sed -E "s/^.*['’]s //" <<<"$alias")"
    done <"$WORK_DIR/bt-aliases.tsv"
}

restore_network() {
    [[ -f "$WORK_DIR/bt-aliases.tsv" ]] || return 0
    local mac alias
    while IFS=$'\t' read -r mac alias; do
        busctl set-property org.bluez "$(bluez_path "$mac")" org.bluez.Device1 Alias s "$alias"
    done <"$WORK_DIR/bt-aliases.tsv"
}

run_hook() {
    local hook="$1_$2"
    declare -F "$hook" >/dev/null && "$hook"
    return 0
}

dispatch() {
    hyprctl dispatch "$1" >/dev/null
}

toggle_shortcut() {
    dispatch "hl.dsp.global(\"quickshell:$1\")"
}

restore_all() {
    restore_clipboard
    restore_network
    if [[ -n "$START_WORKSPACE" ]]; then
        dispatch "hl.dsp.focus({ workspace = $START_WORKSPACE })"
    fi
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
    case "$name" in
        toast)
            notify-send -a "Hyprland dots" "Warm ember applied" \
                "Orange primary, punchier accents across shell, kitty and btop"
            sleep "$TOAST_SECONDS"
            ;;
        *)
            toggle_shortcut "$shortcut"
            sleep "$SETTLE_SECONDS"
            ;;
    esac
    echo "  opened $name" >&2
}

close_popup() {
    local name=$1 shortcut=$2
    if [[ "$name" != toast ]]; then
        toggle_shortcut "$shortcut"
    fi
    sleep 0.8
}

# Writes the finished picture for $1 from its raw capture $2.
finish_shot() {
    local name=$1 capture=$2 baseline=$3 out=$4 box
    box=$(changed_box "$capture" "$baseline")
    if [[ -z "$box" || "$box" == 0x0* ]]; then
        echo "  $name: nothing changed against the baseline, skipped" >&2
        return 1
    fi
    crop_to_box "$capture" "$box" "$out"
}

take_shot() {
    local name=$1 baseline=$2 shortcut capture out
    shortcut=$(shortcut_for "$name")
    capture="$WORK_DIR/$name.png"
    out="$OUT_DIR/$name.png"
    run_hook prep "$name"
    open_popup "$name" "$shortcut"
    grim "$capture"
    close_popup "$name" "$shortcut"
    run_hook restore "$name"
    finish_shot "$name" "$capture" "$baseline" "$out" || return 1
    echo "  wrote screenshots/gallery/$name.png ($(magick identify -format '%wx%h' "$out"))" >&2
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
    trap restore_all EXIT
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
