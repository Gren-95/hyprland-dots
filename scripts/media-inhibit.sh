#!/bin/bash
# media-inhibit.sh - Inhibit idle actions (dim/lock/dpms/suspend) while media
# is playing, via the org.freedesktop.ScreenSaver interface that hypridle owns.
# The inhibitor is held by lib/inhibit.sh (see there for why it needs a
# long-lived D-Bus connection).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/inhibit.sh"

trap inhibit_stop EXIT
trap 'inhibit_stop; exit 0' TERM INT

# Reconcile every poll rather than only on play/pause transitions: inhibit_start
# is a no-op when the holder is already alive and respawns it if it died, so a
# crashed holder self-heals instead of silently leaving media un-inhibited.
# Sleep in the background and wait on it so a TERM is handled immediately.
while true; do
    if [ "$(playerctl status 2>/dev/null)" = "Playing" ]; then
        inhibit_start media-inhibit "Media is playing"
    else
        inhibit_stop
    fi
    sleep 3 &
    wait $!
done
