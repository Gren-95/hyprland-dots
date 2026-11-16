#!/bin/bash
# Shuffle-play ~/Music in a background mpv. Usage: music.sh start|stop|toggle
#
# The player is told apart from any other mpv (a video, a preview) by its IPC
# socket, so stop only stops this one and start never runs a second copy.
# Used by Super+Shift+M / Super+Shift+K and the `music` fish function.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

SOCKET="$RUNTIME_DIR/music-mpv.sock"
PLAYLIST="$RUNTIME_DIR/music-mpv.playlist"

# PIDs of mpv processes started with our socket. Only processes named mpv are
# checked, so a shell or editor whose command line mentions the socket path
# never matches.
player_pid() {
    local pid
    for pid in $(pgrep -x mpv); do
        grep -qzx -- "--input-ipc-server=$SOCKET" "/proc/$pid/cmdline" 2>/dev/null && echo "$pid"
    done
    return 0
}

start() {
    if [[ -n $(player_pid) ]]; then
        echo "music: already playing"
        return 0
    fi
    find "$MUSIC_DIR" -type f \( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.ogg' \
        -o -iname '*.opus' -o -iname '*.m4a' -o -iname '*.wav' -o -iname '*.aac' \) >"$PLAYLIST"
    if [[ ! -s $PLAYLIST ]]; then
        echo "music: no tracks in $MUSIC_DIR" >&2
        return 1
    fi
    setsid -f mpv --no-video --shuffle --title=music --input-ipc-server="$SOCKET" \
        --playlist="$PLAYLIST" >/dev/null 2>&1 </dev/null
}

stop() {
    local pid
    pid=$(player_pid)
    [[ -n $pid ]] && kill $pid
    rm -f "$SOCKET"
}

case ${1:-} in
    start) start ;;
    stop) stop ;;
    toggle) if [[ -n $(player_pid) ]]; then stop; else start; fi ;;
    *)
        echo "usage: music.sh start|stop|toggle" >&2
        exit 2
        ;;
esac
