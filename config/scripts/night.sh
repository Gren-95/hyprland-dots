#!/bin/bash
# night.sh - Night light via hyprsunset.
#
# Usage: night.sh {toggle|on|off|status|resume|apply}
#   status prints "on" or "off".
#   resume starts a scheduled night light quietly (restart.sh, at login).
#   apply  restarts a running night light with the current settings (the
#          settings app runs it after a night-* setting changes).
#
# Settings (settings app, Appearance > Night light):
#   night-temperature   colour temperature in Kelvin (default 4000)
#   night-schedule      1: follow night-from / night-to (default 0)
#   night-from, night-to  HH:MM, default 21:00 and 07:00
#
# With a schedule, "on" runs hyprsunset with profiles written to
# ~/.config/hypr/hyprsunset.conf (the warm colour from night-from, normal
# colour from night-to), so it changes by itself at those times; without one
# "on" turns the warm colour on now. If hyprsunset is not installed, a
# notification says so and the script exits 0.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/settings.sh"

PROFILES="$HYPR_DIR/hyprsunset.conf"
TEMPERATURE=$(valid "$(setting night-temperature 4000)" '[1-9][0-9]{3,4}' 4000)
TIME='([01]?[0-9]|2[0-3]):[0-5][0-9]'
FROM=$(valid "$(setting night-from 21:00)" "$TIME" 21:00)
TO=$(valid "$(setting night-to 07:00)" "$TIME" 07:00)
scheduled() { [[ $(setting night-schedule 0) == 1 ]]; }

is_on() { pgrep -x hyprsunset >/dev/null; }

write_profiles() {
    cat >"$PROFILES" <<EOF
# Written by scripts/night.sh from the night light settings; gitignored.
profile {
    time = $TO
    identity = true
}

profile {
    time = $FROM
    temperature = $TEMPERATURE
}
EOF
}

start() {
    if scheduled; then
        write_profiles
        setsid -f hyprsunset >/dev/null 2>&1
    else
        setsid -f hyprsunset -t "$TEMPERATURE" >/dev/null 2>&1
    fi
}

night_on() {
    is_on && return 0
    start
    if scheduled; then
        notify low night weather-clear-night "Night light" "On from $FROM to $TO (${TEMPERATURE}K)" 2000
    else
        notify low night weather-clear-night "Night light" "On (${TEMPERATURE}K)" 2000
    fi
}

night_off() {
    if is_on; then
        pkill -x hyprsunset || true
        notify low night weather-clear "Night light" "Off" 2000
    fi
}

usage() {
    echo "usage: $0 {toggle|on|off|status|resume|apply}" >&2
    exit 2
}

[[ $# -eq 1 ]] || usage
case "$1" in
    toggle | on | off | status | resume | apply) ;;
    *) usage ;;
esac

if ! command -v hyprsunset >/dev/null 2>&1; then
    [[ $1 == resume || $1 == status || $1 == apply ]] || notify normal night dialog-warning "Night light" "hyprsunset is not installed" 4000
    [[ $1 == status ]] && echo off
    exit 0
fi

case "$1" in
    toggle) if is_on; then night_off; else night_on; fi ;;
    on) night_on ;;
    off) night_off ;;
    status) if is_on; then echo on; else echo off; fi ;;
    resume) if scheduled && ! is_on; then start; fi ;;
    apply)
        if is_on; then
            pkill -x hyprsunset || true
            # Let the old instance hand the gamma back before the new one starts.
            sleep 0.3
            start
        elif scheduled; then
            start
        fi
        ;;
esac
