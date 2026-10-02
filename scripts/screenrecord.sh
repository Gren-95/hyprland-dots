#!/bin/bash
# screenrecord.sh - Toggle screen recording with gpu-screen-recorder
#
# The pidfile lives in $RUNTIME_DIR (private to this user), not /tmp. A flock on
# a sibling lockfile serialises the check-then-start so two quick keypresses
# cannot both start a recorder.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"

PIDFILE="$SCREENRECORD_PID"
LOCKFILE="$RUNTIME_DIR/screenrecord.lock"
START_CHECK_SECONDS=1

mkdir -p "$RECORDINGS_DIR"
exec 9>"$LOCKFILE"
flock -n 9 || exit 0

# True when the pidfile names a live gpu-screen-recorder (guards against a
# stale pidfile whose PID was reused by an unrelated process).
recorder_running() {
    local pid
    [[ -f "$PIDFILE" ]] || return 1
    pid=$(<"$PIDFILE")
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    [[ "$(cat "/proc/$pid/comm" 2>/dev/null)" == gpu-screen-r* ]]
}

if recorder_running; then
    # Stop recording. Process may exit between the check and SIGINT, so don't
    # abort on signal failure — we still want to remove the pidfile.
    kill -SIGINT "$(<"$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
    notify normal screenrecord media-record "Recording stopped" "Saved in $RECORDINGS_DIR" 3000
    exit 0
fi

rm -f "$PIDFILE"
FILE="$RECORDINGS_DIR/$(date +%Y%m%d-%H%M%S).mp4"

# Start recording. `-w screen` uses DRM/KMS direct capture which captures
# everything on the framebuffer (including overlays). The Quickshell HUD
# hides itself while `recording = true` so it doesn't appear in the video.
# fd 9 is closed for the child so it does not keep the lock held.
gpu-screen-recorder -w screen -c mp4 -f 60 -o "$FILE" 9>&- &
pid=$!

# Publish the pidfile at once (the Quickshell HUD polls it), then confirm the
# recorder survived startup; on failure withdraw the pidfile and say so.
echo "$pid" > "$PIDFILE.tmp"
mv -f "$PIDFILE.tmp" "$PIDFILE"

sleep "$START_CHECK_SECONDS"
if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$PIDFILE"
    notify critical screenrecord dialog-error "Recording failed" "gpu-screen-recorder exited right after start" 5000
    exit 1
fi
