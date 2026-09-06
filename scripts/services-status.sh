#!/bin/bash
# One probe for the Services panel: prints `key=value` pairs on a single line,
# which is all the QML has to parse.
#
# Kept out of the QML on purpose — a shell pipeline embedded in a string
# literal is unreadable, untestable and invisible to ShellCheck.
set -uo pipefail

SCRIPTS="$HOME/.config/scripts"

# Session daemons, started by restart.sh at login.
for d in battery-notify power-auto media-inhibit fullscreen-inhibit dotwatch; do
    if pgrep -f "$d\.sh" >/dev/null 2>&1; then
        printf '%s=1 ' "$d"
    else
        printf '%s=0 ' "$d"
    fi
done

if pgrep -x wayvnc >/dev/null 2>&1; then printf 'wayvnc=1 '; else printf 'wayvnc=0 '; fi
printf 'winvm=%s ' "$(bash "$SCRIPTS/winvm-toggle.sh" status 2>/dev/null || echo 0)"

# immich=0|1 jellyfin=0|1
printf '%s ' "$(bash "$SCRIPTS/sync-toggle.sh" status all 2>/dev/null)"

# Next jellyfin run as a unix timestamp, 0 when the timer is inactive. The
# panel formats it; systemd's own string carries a timezone name and spaces.
next=$(systemctl --user show jellyfin-sync.timer -p NextElapseUSecRealtime --value 2>/dev/null)
if [[ -n "$next" ]]; then
    printf 'jfnext=%s' "$(date -d "$next" +%s 2>/dev/null || echo 0)"
else
    printf 'jfnext=0'
fi
printf '\n'
