#!/bin/bash
# Battery low notification daemon
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"

WARNED_20=false
WARNED_10=false

BATTERY=$(find /sys/class/power_supply/ -maxdepth 1 -name "BAT*" 2>/dev/null | sort | head -1)
BATTERY=${BATTERY##*/}

while true; do
    [[ -z "$BATTERY" ]] && { sleep 60; continue; }
    CAPACITY=$(cat "/sys/class/power_supply/$BATTERY/capacity" 2>/dev/null)
    STATUS=$(cat "/sys/class/power_supply/$BATTERY/status" 2>/dev/null)

    if [[ "$STATUS" == "Charging" || "$STATUS" == "Full" ]]; then
        if [[ "$WARNED_10" == true || "$WARNED_20" == true ]]; then
            swaync-client --close-latest
        fi
        WARNED_20=false
        WARNED_10=false
    elif [[ -n "$CAPACITY" ]]; then
        if [[ "$CAPACITY" -le 10 && "$WARNED_10" == false ]]; then
            notify critical battery battery-caution "Battery Critical" "${CAPACITY}% remaining — plug in now!"
            WARNED_10=true
        elif [[ "$CAPACITY" -le 20 && "$WARNED_20" == false ]]; then
            notify normal battery battery-low "Battery Low" "${CAPACITY}% remaining"
            WARNED_20=true
        fi
    fi

    sleep 60
done
