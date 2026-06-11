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

COOKIE=""

inhibit() {
    COOKIE=$(gdbus call --session \
        --dest org.freedesktop.ScreenSaver \
        --object-path /org/freedesktop/ScreenSaver \
        --method org.freedesktop.ScreenSaver.Inhibit \
        "fullscreen-inhibit" "Fullscreen application" 2>/dev/null | grep -oP '\d+')
}

uninhibit() {
    if [ -n "$COOKIE" ]; then
        gdbus call --session \
            --dest org.freedesktop.ScreenSaver \
            --object-path /org/freedesktop/ScreenSaver \
            --method org.freedesktop.ScreenSaver.UnInhibit \
            "uint32 $COOKIE" >/dev/null 2>&1
        COOKIE=""
    fi
}

trap uninhibit EXIT TERM INT

INHIBITED=false

while true; do
    # True if any workspace (on any monitor) has a fullscreen window.
    if hyprctl workspaces -j 2>/dev/null | jq -e 'any(.[]; .hasfullscreen // false)' >/dev/null 2>&1; then
        FS=true
    else
        FS=false
    fi

    if [ "$FS" = true ] && [ "$INHIBITED" = false ]; then
        inhibit
        INHIBITED=true
    elif [ "$FS" = false ] && [ "$INHIBITED" = true ]; then
        uninhibit
        INHIBITED=false
    fi
    sleep 5
done
