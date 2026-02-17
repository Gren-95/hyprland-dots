#!/bin/bash
# Battery low notification daemon

WARNED_20=false
WARNED_10=false

while true; do
    CAPACITY=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || cat /sys/class/power_supply/BAT1/capacity 2>/dev/null)
    STATUS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || cat /sys/class/power_supply/BAT1/status 2>/dev/null)

    if [[ "$STATUS" == "Charging" || "$STATUS" == "Full" ]]; then
        WARNED_20=false
        WARNED_10=false
    elif [[ -n "$CAPACITY" ]]; then
        if [[ "$CAPACITY" -le 10 && "$WARNED_10" == false ]]; then
            notify-send -u critical -i battery-caution "Battery Critical" "${CAPACITY}% remaining — plug in now!"
            WARNED_10=true
        elif [[ "$CAPACITY" -le 20 && "$WARNED_20" == false ]]; then
            notify-send -u normal -i battery-low "Battery Low" "${CAPACITY}% remaining"
            WARNED_20=true
        fi
    fi

    sleep 60
done
