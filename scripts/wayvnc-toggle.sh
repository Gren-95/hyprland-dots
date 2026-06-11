#!/bin/bash
set -euo pipefail

# Toggle the WayVNC remote-access server. State is shown by the bar's
# remote-access status icon, so no notification is sent.
if pgrep -x wayvnc > /dev/null; then
    pkill wayvnc || true
else
    wayvnc &>/dev/null &
fi
