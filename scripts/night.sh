#!/bin/bash
# night.sh - Night light via hyprsunset.
#
# Usage: night.sh {toggle|on|off|status}
#   status prints "on" or "off".
#
# Colour temperature comes from NIGHT_TEMPERATURE in scripts/util.env (Kelvin,
# see util.env.example); 4000 is used when it is unset.
# If hyprsunset is not installed, a notification says so and the script exits 0.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/env.sh"

load_util_env
TEMPERATURE="${NIGHT_TEMPERATURE:-4000}"

if ! [[ "$TEMPERATURE" =~ ^[0-9]+$ ]]; then
    echo "night.sh: NIGHT_TEMPERATURE must be a whole number of Kelvin, got '$TEMPERATURE'" >&2
    exit 1
fi

is_on() { pgrep -x hyprsunset >/dev/null; }

night_on() {
    is_on && return 0
    setsid -f hyprsunset -t "$TEMPERATURE" >/dev/null 2>&1
    notify low night weather-clear-night "Night light" "On (${TEMPERATURE}K)" 2000
}

night_off() {
    if is_on; then
        pkill -x hyprsunset || true
        notify low night weather-clear "Night light" "Off" 2000
    fi
}

usage() { echo "usage: $0 {toggle|on|off|status}" >&2; exit 2; }

[[ $# -eq 1 ]] || usage
case "$1" in
    toggle|on|off|status) ;;
    *) usage ;;
esac

if ! command -v hyprsunset >/dev/null 2>&1; then
    notify normal night dialog-warning "Night light" "hyprsunset is not installed" 4000
    exit 0
fi

case "$1" in
    toggle) if is_on; then night_off; else night_on; fi ;;
    on)     night_on ;;
    off)    night_off ;;
    status) if is_on; then echo on; else echo off; fi ;;
esac
