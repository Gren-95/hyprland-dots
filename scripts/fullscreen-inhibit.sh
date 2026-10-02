#!/bin/bash
# fullscreen-inhibit.sh - Inhibit idle while any window is fullscreen.
#
# Game controllers (and some Proton games) don't reset the Wayland idle timer,
# so hypridle would dim the screen, switch the keyboard backlight off, lock and
# eventually suspend mid-game. Holding an org.freedesktop.ScreenSaver inhibit
# (honored by hypridle, same mechanism as media-inhibit.sh) while a fullscreen
# window exists prevents that. The inhibit is released as soon as nothing is
# fullscreen, so normal idle/power-saving resumes on the desktop.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/inhibit.sh"

trap inhibit_stop EXIT
trap 'inhibit_stop; exit 0' TERM INT

# Reconcile every poll (not just on transitions): inhibit_start is a no-op when
# the holder is already alive and respawns it if it died, so a crashed holder
# self-heals instead of silently leaving a fullscreen app un-inhibited.
while true; do
    if hyprctl workspaces -j 2>/dev/null | jq -e 'any(.[]; .hasfullscreen // false)' >/dev/null 2>&1; then
        inhibit_start fullscreen-inhibit "Fullscreen application"
    else
        inhibit_stop
    fi
    sleep 5 &
    wait $!
done
