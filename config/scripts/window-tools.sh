#!/bin/bash
# window-tools.sh — actions on the focused window that need its state from hyprctl.
#
# Usage:
#   window-tools.sh tiled-fullscreen   toggle tiled fullscreen: the app believes it
#                                      is fullscreen, the compositor keeps it tiled
#   window-tools.sh width save         remember the window's width (per app and workspace)
#   window-tools.sh width restore      resize the window back to the remembered width
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"

readonly STATE_DIR="$HOME/.local/state/window-tools"
# Resizing a tiled window moves its nearest edge, so the first guess can go the
# wrong way. Each attempt re-measures and flips direction when it got worse.
readonly MAX_RESIZE_ATTEMPTS=5

dispatch() {
    hyprctl dispatch "$1" >/dev/null
}

tiled_fullscreen() {
    local client
    client=$(hyprctl activewindow -j | jq -r '.fullscreenClient // 0')
    if [[ $client == 2 ]]; then
        dispatch 'hl.dsp.window.fullscreen_state({ internal = 0, client = 0 })'
    else
        dispatch 'hl.dsp.window.fullscreen_state({ internal = 0, client = 2 })'
    fi
}

active_width() {
    hyprctl activewindow -j | jq -r '.size[0]'
}

# Path of the state file for the focused window: one width per app and workspace.
width_file() {
    local info app workspace
    info=$(hyprctl activewindow -j)
    app=$(jq -r '.class // empty' <<<"$info")
    workspace=$(jq -r '.workspace.id // empty' <<<"$info")
    [[ -n $app && -n $workspace ]] || return 1
    printf '%s/ws%s-%s.width' "$STATE_DIR" "$workspace" "${app//[^A-Za-z0-9._-]/_}"
}

save_width() {
    local file width
    file=$(width_file) || return 1
    width=$(active_width)
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$width" >"$file"
    notify low window-tools view-restore "Window width saved" "${width}px, restore it with Super+Home"
}

abs_diff() {
    local d=$(($1 - $2))
    echo "${d#-}"
}

restore_width() {
    local file target current gap previous_gap=-1 direction=1 attempt
    file=$(width_file) || return 1
    if [[ ! -f $file ]]; then
        notify low window-tools view-restore "No saved width" "Save one with Super+Alt+Home"
        return 1
    fi
    target=$(<"$file")
    [[ $target =~ ^[0-9]+$ ]] || return 1

    for ((attempt = 0; attempt < MAX_RESIZE_ATTEMPTS; attempt++)); do
        current=$(active_width)
        gap=$(abs_diff "$current" "$target")
        ((gap == 0)) && return 0
        # The last resize moved the window away from the target: it grows the other way.
        ((previous_gap >= 0 && gap > previous_gap)) && direction=$((-direction))
        previous_gap=$gap
        dispatch "hl.dsp.window.resize({ x = $(((target - current) * direction)), y = 0, relative = true })"
    done
    current=$(active_width)
    ((current == target)) || notify low window-tools view-restore "Width not restored" "Reached ${current}px of ${target}px"
}

case "${1:-}:${2:-}" in
    tiled-fullscreen:) tiled_fullscreen ;;
    width:save) save_width ;;
    width:restore) restore_width ;;
    *)
        echo "Usage: window-tools.sh tiled-fullscreen | width save|restore" >&2
        exit 1
        ;;
esac
