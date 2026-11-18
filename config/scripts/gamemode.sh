#!/bin/bash
# gamemode.sh - Game mode: strip desktop effects, force the performance power
# profile, and tell Quickshell to hide the bar and enable Do Not Disturb.
#
# Also pauses background work and resumes only what it paused: the Immich and
# Jellyfin syncs (sync-toggle.sh), night light (hyprsunset) and running Docker
# containers (`docker pause`; stopping dockerd itself needs root). It also holds
# an idle inhibitor so hypridle never dims or locks during gamepad-only play.
#
# Usage: gamemode.sh {toggle|on|off|status|feral}
#   status prints "on" or "off".
#   feral  writes or removes ~/.config/gamemode.ini so Feral GameMode
#          (games started with `gamemoderun`) turns game mode on and off.
#
# Settings (settings app, Gaming), each 1 (default) or 0:
#   gamemode-effects      Hyprland animations, blur, shadows, gaps, rounding off
#   gamemode-performance  the performance power profile
#   gamemode-syncs        pause the Immich and Jellyfin syncs
#   gamemode-night        pause night light
#   gamemode-docker       pause running Docker containers
#   gamemode-awake        keep the screen from dimming and locking
#   gamemode-feral        follow Feral GameMode (default 0; see feral)
# Hiding the bar, Do Not Disturb and pausing Tailscale are done by
# Quickshell (gamemode-hide-bar, gamemode-dnd, gamemode-tailscale).
#
# State lives in $XDG_RUNTIME_DIR/gamemode: "off", or "on <previous profile>".
# Quickshell watches that file (GameModeService.qml) for the bar and DND.
# Leaving game mode runs `hyprctl reload`, which re-applies every Lua module
# plus hyprland-gui.lua, so nothing needs to be saved for the Hyprland side.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/inhibit.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/settings.sh"

# Whether game mode does `$1` (a gamemode-* setting, on unless set to 0).
does() { [[ $(setting "gamemode-$1" 1) != 0 ]]; }

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

    status=""
    does syncs && status=$(bash "$SYNC_TOGGLE" status all 2>/dev/null || true)
    for kind in immich jellyfin; do
        if [[ "$status" == *"$kind=1"* ]]; then
            bash "$SYNC_TOGGLE" disable "$kind" >/dev/null 2>&1 || true
            echo "sync_$kind=1" >>"$PAUSED_FILE"
        fi
    done

    if does night && [[ "$(bash "$NIGHT" status 2>/dev/null)" == on ]]; then
        bash "$NIGHT" off >/dev/null 2>&1 || true
        echo "night=1" >>"$PAUSED_FILE"
    fi

    # Detach the holder from our stdout/stderr so a caller waiting on the pipe
    # (Quickshell, exec_cmd) is not kept waiting for it.
    if does awake; then
        inhibit_start gamemode "Game mode" >/dev/null 2>&1
        echo "inhibit=$INHIBIT_HOLDER_PID" >>"$PAUSED_FILE"
    fi

    if does docker && command -v docker >/dev/null 2>&1; then
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

    if does effects; then
        hyprctl eval 'hl.config({
            animations = { enabled = false },
            general = { gaps_in = 0, gaps_out = 0, border_size = 1 },
            decoration = { rounding = 0, blur = { enabled = false }, shadow = { enabled = false } },
        })' >/dev/null
    fi
    does performance && { powerprofilesctl set "$GAME_PROFILE" 2>/dev/null || true; }
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

# Feral GameMode runs the [custom] start/end commands of ~/.config/gamemode.ini
# when a game started with `gamemoderun` opens and closes. The file is only
# removed again if this script wrote it (the marker on its first line).
FERAL_INI="${XDG_CONFIG_HOME:-$HOME/.config}/gamemode.ini"
FERAL_MARKER="; Written by gamemode.sh (dots). Remove this line to keep your own edits."
feral() {
    local ours=0
    [[ -f "$FERAL_INI" && "$(head -n1 "$FERAL_INI")" == "$FERAL_MARKER" ]] && ours=1
    if [[ $(setting gamemode-feral 0) == 1 ]]; then
        if [[ -f "$FERAL_INI" && $ours == 0 ]]; then
            notify normal gamemode input-gaming "Game mode" "$FERAL_INI already exists; add start/end under [custom] by hand" 6000
            return 0
        fi
        local self
        self=$(realpath "$0")
        printf '%s\n[custom]\nstart=bash %s on\nend=bash %s off\n' "$FERAL_MARKER" "$self" "$self" >"$FERAL_INI"
    elif [[ $ours == 1 ]]; then
        rm -f "$FERAL_INI"
    fi
}

usage() {
    echo "usage: $0 {toggle|on|off|status|feral}" >&2
    exit 2
}

[[ $# -eq 1 ]] || usage
case "$1" in
    toggle) if is_on; then game_off; else game_on; fi ;;
    on) game_on ;;
    off) game_off ;;
    status) state_word ;;
    feral) feral ;;
    *) usage ;;
esac
