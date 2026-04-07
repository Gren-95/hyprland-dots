#!/bin/bash
# screenrecord.sh - Toggle screen recording with gpu-screen-recorder
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

mkdir -p "$RECORDINGS_DIR"
FILE="$RECORDINGS_DIR/$(date +%Y%m%d-%H%M%S).mp4"
PIDFILE="$SCREENRECORD_PID"

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    # Stop recording
    kill -SIGINT "$(cat "$PIDFILE")"
    rm -f "$PIDFILE"
    notify-send "Screen Recording" "Saved to $RECORDING_DIR" -i video-x-generic -t 4000
else
    # Start recording
    gpu-screen-recorder -w screen -c mp4 -f 60 -o "$FILE" &
    echo $! > "$PIDFILE"
    notify-send "Screen Recording" "Recording started" -i media-record -t 2000
fi
