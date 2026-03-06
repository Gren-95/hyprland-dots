#!/bin/bash
# media-inhibit.sh - Inhibit screen sleep/lock while media is playing
# Uses the org.freedesktop.ScreenSaver D-Bus interface (supported by hypridle)

COOKIE=""

inhibit() {
    COOKIE=$(gdbus call --session \
        --dest org.freedesktop.ScreenSaver \
        --object-path /org/freedesktop/ScreenSaver \
        --method org.freedesktop.ScreenSaver.Inhibit \
        "media-inhibit" "Media is playing" 2>/dev/null | grep -oP '\d+')
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

IS_PLAYING=false

while true; do
    STATUS=$(playerctl status 2>/dev/null)
    if [ "$STATUS" = "Playing" ]; then
        if [ "$IS_PLAYING" = false ]; then
            inhibit
            IS_PLAYING=true
        fi
    else
        if [ "$IS_PLAYING" = true ]; then
            uninhibit
            IS_PLAYING=false
        fi
    fi
    sleep 3
done
