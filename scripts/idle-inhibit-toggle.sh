#!/bin/bash
# idle-inhibit-toggle.sh - Manually block idle (dim/lock/suspend) until toggled
# off, via the shared ScreenSaver inhibitor holder in lib/inhibit.sh.
#
# The holder process outlives this script; its PID is kept in
# $RUNTIME_DIR/idle-inhibit.pid. Releasing = killing the holder.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/inhibit.sh"

PIDFILE="$RUNTIME_DIR/idle-inhibit.pid"
START_CHECK_SECONDS=1

# True when the pidfile names a live holder (python3), not a recycled PID.
holder_running() {
    local pid
    [[ -f "$PIDFILE" ]] || return 1
    pid=$(<"$PIDFILE")
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    [[ "$(cat "/proc/$pid/comm" 2>/dev/null)" == python3* ]]
}

if holder_running; then
    kill "$(<"$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
    notify low idle-inhibit preferences-system-time "Idle inhibit" "Off: the screen may lock and sleep again" 2500
    exit 0
fi

rm -f "$PIDFILE"
# Detach the holder from our stdout/stderr so a caller waiting on the pipe
# (Quickshell, exec_cmd) is not kept waiting for it.
inhibit_start idle-inhibit-toggle "Manual idle inhibit" >/dev/null 2>&1
echo "$INHIBIT_HOLDER_PID" > "$PIDFILE.tmp"
mv -f "$PIDFILE.tmp" "$PIDFILE"

sleep "$START_CHECK_SECONDS"
if ! kill -0 "$INHIBIT_HOLDER_PID" 2>/dev/null; then
    rm -f "$PIDFILE"
    notify critical idle-inhibit dialog-error "Idle inhibit" "Could not register the inhibitor (is hypridle running?)" 4000
    exit 1
fi
notify low idle-inhibit preferences-system-time "Idle inhibit" "On: the screen will stay awake" 2500
