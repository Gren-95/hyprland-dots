#!/bin/bash
# Toggle the WayVNC remote-access server. State is shown by the bar's
# remote-access status icon, so success sends no notification.
#
# wayvnc/config binds loopback (no auth). When Tailscale is up, the tailnet IPv4
# address is passed on the command line instead, so the server is reachable
# over the tailnet only and never on the LAN.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"

PORT=5900
READY_TIMEOUT_DS=30 # deciseconds

if pgrep -x wayvnc >/dev/null; then
    pkill -x wayvnc || true
    exit 0
fi

args=()
if command -v tailscale >/dev/null 2>&1; then
    ts_ip=$(tailscale ip -4 2>/dev/null | head -n 1 || true)
    [[ -n "$ts_ip" ]] && args=("$ts_ip" "$PORT")
fi

wayvnc "${args[@]}" &>/dev/null &

# Readiness: wait until something listens on the port, or give up and say so.
for ((i = 0; i < READY_TIMEOUT_DS; i++)); do
    if ss -ltn "sport = :$PORT" | grep -q LISTEN; then
        exit 0
    fi
    sleep 0.1
done

pkill -x wayvnc || true
notify critical wayvnc dialog-error "Remote access" "wayvnc did not start listening on port $PORT" 5000
exit 1
