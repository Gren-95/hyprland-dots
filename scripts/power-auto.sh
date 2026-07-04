#!/bin/bash
# power-auto.sh — switch power-profiles-daemon profile based on AC + battery%.
#
# Policy:
#   On AC                       → performance
#   On battery, ≥ LOW_THRESHOLD → balanced
#   On battery, < LOW_THRESHOLD → power-saver
#
# Listens to UPower's monitor stream (`upower --monitor-detail`) so it
# reacts on AC plug events AND on battery percentage updates.
# Started from hypr/modules/autostart.conf.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"

LOW_THRESHOLD=30   # below this %, drop to power-saver

# Read current state ("yes"/"no") and percentage from UPower.
read_state() {
    upower -i /org/freedesktop/UPower/devices/DisplayDevice 2>/dev/null
}

current_on_bat() {
    local s
    s=$(read_state | awk -F': *' '/state:/ {print $2; exit}')
    case "$s" in
        discharging|pending-discharge) echo yes ;;
        *)                              echo no ;;
    esac
}
current_pct() {
    read_state | awk -F': *' '/percentage:/ {gsub(/%/,"",$2); print $2; exit}'
}

decide() {
    local on_bat=$1 pct=$2
    # UPower can emit fractional percentages (e.g. "85.6"). Bash arithmetic
    # would error on the decimal — truncate to the integer part.
    pct=${pct%%.*}
    if [[ "$on_bat" != "yes" ]]; then
        echo performance
    elif [[ -n "$pct" && "$pct" -lt "$LOW_THRESHOLD" ]]; then
        echo power-saver
    else
        echo balanced
    fi
}

apply() {
    local target=$1
    local cur
    cur=$(powerprofilesctl get 2>/dev/null)
    [[ "$cur" == "$target" ]] && return 0
    powerprofilesctl set "$target" 2>/dev/null || return 1

    local label="$target" icon="power-profile-$target-symbolic"
    case "$target" in
        performance) label="Performance (on AC)" ;;
        balanced)    label="Balanced (on battery)" ;;
        power-saver) label="Power Saver (battery < ${LOW_THRESHOLD}%)" ;;
    esac
    notify low power-profile "$icon" "Power" "Switched to $label"
}

react() {
    apply "$(decide "$(current_on_bat)" "$(current_pct)")"
}

# Initial state on startup.
react

# Watch for events. upower emits property changes (including percentage
# updates) — we just re-derive on any on-battery / percentage line.
upower --monitor-detail 2>/dev/null | while read -r line; do
    case "$line" in
        *"on-battery:"*|*"percentage:"*) react ;;
    esac
done
