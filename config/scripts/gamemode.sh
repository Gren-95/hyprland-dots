#!/bin/bash
# gamemode.sh - Game mode: strip desktop effects, force the performance power
# profile, and tell Quickshell to hide the bar and enable Do Not Disturb.
#
# Also pauses background work and resumes only what it paused: the Immich and
# Jellyfin syncs (sync-toggle.sh), night light (hyprsunset) and running Docker
# containers (`docker pause`; stopping dockerd itself needs root). It also holds
# an idle inhibitor so hypridle never dims or locks during gamepad-only play.
#
# Usage: gamemode.sh {toggle|on|off|status}
#   status prints "on" or "off".
#
# State lives in $XDG_RUNTIME_DIR/gamemode: "off", or "on <previous profile>".
# Quickshell watches that file (GameModeService.qml) for the bar and DND.
# Leaving game mode runs `hyprctl reload`, which re-applies every Lua module
# plus hyprland-gui.lua, so nothing needs to be saved for the Hyprland side.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/inhibit.sh"

STATE_FILE="$RUNTIME_DIR/gamemode"
# What game mode paused, one "key=value" per line, so only that is resumed.
PAUSED_FILE="$RUNTIME_DIR/gamemode.paused"
SYNC_TOGGLE="$SCRIPTS_DIR/sync-toggle.sh"
NIGHT="$SCRIPTS_DIR/night.sh"
GAME_PROFILE="performance"
FALLBACK_PROFILE="balanced"

state_word() {
    local state=off
    [[ -f "$STATE_FILE" ]] && read -r state _ <"$STATE_FILE"
    echo "$state"
}

is_on() { [[ "$(state_word)" == on ]]; }

write_state() {
    printf '%s\n' "$1" >"$STATE_FILE.tmp"
    mv -f "$STATE_FILE.tmp" "$STATE_FILE"
}

previous_profile() {
    local profile=""
    [[ -f "$STATE_FILE" ]] && read -r _ profile <"$STATE_FILE"
    echo "${profile:-$FALLBACK_PROFILE}"
}

paused_value() {
    [[ -f "$PAUSED_FILE" ]] && sed -n "s/^$1=//p" "$PAUSED_FILE" | head -n1
}

pause_background() {
    local status kind containers=""
    : >"$PAUSED_FILE"

    status=$(bash "$SYNC_TOGGLE" status all 2>/dev/null || true)
    for kind in immich jellyfin; do
        if [[ "$status" == *"$kind=1"* ]]; then
            bash "$SYNC_TOGGLE" disable "$kind" >/dev/null 2>&1 || true
            echo "sync_$kind=1" >>"$PAUSED_FILE"
        fi
    done

    if [[ "$(bash "$NIGHT" status 2>/dev/null)" == on ]]; then
        bash "$NIGHT" off >/dev/null 2>&1 || true
        echo "night=1" >>"$PAUSED_FILE"
    fi

    # Detach the holder from our stdout/stderr so a caller waiting on the pipe
    # (Quickshell, exec_cmd) is not kept waiting for it.
    inhibit_start gamemode "Game mode" >/dev/null 2>&1
    echo "inhibit=$INHIBIT_HOLDER_PID" >>"$PAUSED_FILE"

    if command -v docker >/dev/null 2>&1; then
        containers=$(docker ps --filter status=running -q 2>/dev/null | tr '\n' ' ' || true)
        if [[ -n "${containers// /}" ]]; then
            # shellcheck disable=SC2086  # ids are hex words
            docker pause $containers >/dev/null 2>&1 || containers=""
            echo "docker=${containers% }" >>"$PAUSED_FILE"
        fi
    fi
}

resume_background() {
    local kind containers holder_pid
    holder_pid=$(paused_value inhibit)
    # Only kill a live python3 holder, not a recycled PID.
    if [[ "$holder_pid" =~ ^[0-9]+$ && "$(cat "/proc/$holder_pid/comm" 2>/dev/null)" == python3* ]]; then
        kill "$holder_pid" 2>/dev/null || true
    fi

    for kind in immich jellyfin; do
        if [[ "$(paused_value "sync_$kind")" == 1 ]]; then
            bash "$SYNC_TOGGLE" enable "$kind" >/dev/null 2>&1 || true
        fi
    done

    if [[ "$(paused_value night)" == 1 ]]; then
        bash "$NIGHT" on >/dev/null 2>&1 || true
    fi

    containers=$(paused_value docker)
    if [[ -n "$containers" ]]; then
        # shellcheck disable=SC2086
        docker unpause $containers >/dev/null 2>&1 || true
    fi
    rm -f "$PAUSED_FILE"
}

game_on() {
    is_on && return 0
    local profile
    profile=$(powerprofilesctl get 2>/dev/null || echo "$FALLBACK_PROFILE")

    hyprctl eval 'hl.config({
        animations = { enabled = false },
        general = { gaps_in = 0, gaps_out = 0, border_size = 1 },
        decoration = { rounding = 0, blur = { enabled = false }, shadow = { enabled = false } },
    })' >/dev/null
    powerprofilesctl set "$GAME_PROFILE" 2>/dev/null || true
    pause_background
    write_state "on $profile"
    notify low gamemode input-gaming "Game mode" "On" 2000
}

game_off() {
    is_on || return 0
    local profile
    profile=$(previous_profile)

    write_state off
    hyprctl reload >/dev/null
    powerprofilesctl set "$profile" 2>/dev/null || true
    resume_background
    notify low gamemode input-gaming "Game mode" "Off" 2000
}

usage() {
    echo "usage: $0 {toggle|on|off|status}" >&2
    exit 2
}

[[ $# -eq 1 ]] || usage
case "$1" in
    toggle) if is_on; then game_off; else game_on; fi ;;
    on) game_on ;;
    off) game_off ;;
    status) state_word ;;
    *) usage ;;
esac
