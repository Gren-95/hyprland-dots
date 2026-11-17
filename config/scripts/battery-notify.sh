#!/bin/bash
# Battery low notification daemon. The two warning levels come from the
# settings store (settings app, Power panel): battery-low-pct (default 20) and
# battery-warn-pct for the critical warning (default 10); read every minute.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/settings.sh"

WARNED_LOW=false
WARNED_CRITICAL=false

BATTERY=$(find /sys/class/power_supply/ -maxdepth 1 -name "BAT*" 2>/dev/null | sort | head -1)
BATTERY=${BATTERY##*/}

while true; do
    [[ -z "$BATTERY" ]] && {
        sleep 60
        continue
    }
    CAPACITY=$(cat "/sys/class/power_supply/$BATTERY/capacity" 2>/dev/null)
    STATUS=$(cat "/sys/class/power_supply/$BATTERY/status" 2>/dev/null)

    if [[ "$STATUS" != "Discharging" ]]; then
        # On external power: Charging, Full, or "Not charging" when a charge
        # threshold holds the battery below full. Reset the latch so the next
        # discharge cycle can re-warn. Existing
        # warnings are cleared from both the toast stack and the notification
        # center by Notifications.qml as soon as UPower reports power.
        WARNED_LOW=false
        WARNED_CRITICAL=false
    elif [[ -n "$CAPACITY" ]]; then
        LOW=$(valid "$(setting battery-low-pct 20)" '[0-9]{1,2}' 20)
        CRITICAL=$(valid "$(setting battery-warn-pct 10)" '[0-9]{1,2}' 10)
        if [[ "$CAPACITY" -le $CRITICAL && "$WARNED_CRITICAL" == false ]]; then
            notify critical battery battery-caution "Battery Critical" "${CAPACITY}% remaining — plug in now!"
            WARNED_CRITICAL=true
        elif [[ "$CAPACITY" -le $LOW && "$WARNED_LOW" == false ]]; then
            notify normal battery battery-low "Battery Low" "${CAPACITY}% remaining"
            WARNED_LOW=true
        fi
    fi

    sleep 60
done
