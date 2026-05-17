#!/bin/bash
# screenrecord.sh - Toggle screen recording with gpu-screen-recorder
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

mkdir -p "$RECORDINGS_DIR"
FILE="$RECORDINGS_DIR/$(date +%Y%m%d-%H%M%S).mp4"
PIDFILE="$SCREENRECORD_PID"

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    # Stop recording. Process may exit between kill -0 and SIGINT, so don't
    # abort on signal failure — we still want to remove the stale pidfile.
    kill -SIGINT "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
else
    # Start recording. `-w screen` uses DRM/KMS direct capture which captures
    # everything on the framebuffer (including overlays). The Quickshell HUD
    # hides itself while `recording = true` so it doesn't appear in the video.
    gpu-screen-recorder -w screen -c mp4 -f 60 -o "$FILE" &
    echo $! > "$PIDFILE"
fi
