#!/bin/bash
# screenrecord.sh - Toggle screen recording with gpu-screen-recorder
#
# The pidfile lives in $RUNTIME_DIR (private to this user), not /tmp. A flock on
# a sibling lockfile serialises the check-then-start so two quick keypresses
# cannot both start a recorder.
#
# Options come from the shell's settings store (the Recording panel of the
# settings app writes them): record-dir, record-container, record-fps,
# record-quality, record-codec, record-cursor, record-audio. A missing or
# invalid value uses its default.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/shell-ipc.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/settings.sh"

PIDFILE="$SCREENRECORD_PID"
LOCKFILE="$RUNTIME_DIR/screenrecord.lock"
START_CHECK_SECONDS=1
dir=$(setting_dir record-dir "$RECORDINGS_DIR")
container=$(valid "$(setting record-container mp4)" 'mp4|mkv|webm' mp4)
fps=$(valid "$(setting record-fps 60)" '[1-9][0-9]{0,2}' 60)
quality=$(valid "$(setting record-quality very_high)" 'medium|high|very_high|ultra' very_high)
codec=$(valid "$(setting record-codec auto)" 'auto|h264|hevc|av1|vp9' auto)
cursor=yes
[[ $(setting record-cursor 1) == 0 ]] && cursor=no
audio_args=()
case $(setting record-audio none) in
    output) audio_args=(-a default_output) ;;
    input) audio_args=(-a default_input) ;;
    both) audio_args=(-a "default_output|default_input") ;;
esac

mkdir -p "$dir"
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
    shell_ipc recorder stopped
    notify normal screenrecord media-record "Recording stopped" "Saved in $dir" 3000
    exit 0
fi

rm -f "$PIDFILE"
FILE="$dir/$(date +%Y%m%d-%H%M%S).$container"

# Start recording. `-w screen` uses DRM/KMS direct capture which captures
# everything on the framebuffer (including overlays). The Quickshell HUD
# hides itself while `recording = true` so it doesn't appear in the video.
# fd 9 is closed for the child so it does not keep the lock held.
gpu-screen-recorder -w screen -c "$container" -f "$fps" -q "$quality" -k "$codec" \
    -cursor "$cursor" "${audio_args[@]}" -o "$FILE" 9>&- &
pid=$!

# Publish the pidfile at once and tell the Quickshell HUD, then confirm the
# recorder survived startup; on failure withdraw the pidfile and say so.
echo "$pid" >"$PIDFILE.tmp"
mv -f "$PIDFILE.tmp" "$PIDFILE"
shell_ipc recorder started "$(date +%s)"

sleep "$START_CHECK_SECONDS"
if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$PIDFILE"
    shell_ipc recorder stopped
    notify critical screenrecord dialog-error "Recording failed" "gpu-screen-recorder exited right after start" 5000
    exit 1
fi
