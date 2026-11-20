#!/bin/bash
# power-auto.sh — switch power-profiles-daemon profile based on AC + battery%.
#
# Policy (Power in the settings app; the defaults in brackets):
#   On AC                        → power-on-ac [performance]
#   On battery                   → power-on-battery [balanced]
#   On battery, < power-saver-below % → power-saver [30; 0 turns it off]
#
# Usage: power-auto.sh         watch UPower and follow the policy
#        power-auto.sh once    apply the policy now and exit (after a change)
#
# Listens to UPower's monitor stream (`upower --monitor-detail`) so it
# reacts on AC plug events AND on battery percentage updates.
# Started from hypr/modules/autostart.conf.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/settings.sh"

PROFILES='performance|balanced|power-saver'

# Read on every decision, so a change in the settings app counts at once.
read_policy() {
    ON_AC=$(valid "$(setting power-on-ac performance)" "$PROFILES" performance)
    ON_BATTERY=$(valid "$(setting power-on-battery balanced)" "$PROFILES" balanced)
    LOW_THRESHOLD=$(valid "$(setting power-saver-below 30)" '[0-9]{1,2}' 30)
}

# Read current state ("yes"/"no", or "unknown" when UPower does not answer)
# and percentage from UPower.
read_state() {
    upower -i /org/freedesktop/UPower/devices/DisplayDevice 2>/dev/null
}

current_on_bat() {
    local info s
    info=$(read_state)
    # No answer is not "on the charger": keep the profile rather than switch
    # a laptop on battery to the charger's profile.
    [[ -n $info ]] || {
        echo unknown
        return
    }
    s=$(awk -F': *' '/state:/ {print $2; exit}' <<<"$info")
    case "$s" in
        discharging | pending-discharge) echo yes ;;
        *) echo no ;;
    esac
}
current_pct() {
    read_state | awk -F': *' '/percentage:/ {gsub(/%/,"",$2); print $2; exit}'
}

decide() {
    local on_bat=$1 pct=$2
    # UPower can emit fractional percentages, "85.6", or "85,6" under a
    # decimal-comma locale such as et_EE. Truncate at either separator: bash
    # would read "85,6" as a comma expression worth 6.
    pct=${pct%%[.,]*}
    read_policy
    if [[ "$on_bat" != "yes" ]]; then
        echo "$ON_AC"
    elif [[ -n "$pct" && "$pct" -lt "$LOW_THRESHOLD" ]]; then
        echo power-saver
    else
        echo "$ON_BATTERY"
    fi
}

apply() {
    local target=$1
    # Game mode pins the performance profile; gamemode.sh restores it on exit.
    [[ -f "${XDG_RUNTIME_DIR:-/run/user/$UID}/gamemode" ]] &&
        [[ "$(cut -d' ' -f1 "${XDG_RUNTIME_DIR:-/run/user/$UID}/gamemode")" == on ]] && return 0
    local cur
    cur=$(powerprofilesctl get 2>/dev/null)
    [[ "$cur" == "$target" ]] && return 0
    powerprofilesctl set "$target" 2>/dev/null || return 1

    local label="$target" icon="power-profile-$target-symbolic"
    case "$target" in
        performance) label="Performance" ;;
        balanced) label="Balanced" ;;
        power-saver) label="Power Saver" ;;
    esac
    notify low power-profile "$icon" "Power" "Switched to $label"
}

react() {
    local on_bat
    on_bat=$(current_on_bat)
    [[ $on_bat == unknown ]] && return 0
    apply "$(decide "$on_bat" "$(current_pct)")"
}

command -v upower >/dev/null || {
    echo "power-auto: upower is not installed" >&2
    exit 1
}

# Initial state on startup.
react
[[ ${1:-} == once ]] && exit 0

# Watch for events. upower emits property changes (including percentage
# updates) — we just re-derive on any on-battery / percentage line. When the
# monitor ends (UPower restarted), read the state again and watch again.
while true; do
    upower --monitor-detail 2>/dev/null | while read -r line; do
        case "$line" in
            *"on-battery:"* | *"percentage:"*) react ;;
        esac
    done
    sleep 5
    react
done
