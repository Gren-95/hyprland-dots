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

HOLDER_PID=""

# A ScreenSaver inhibitor is released the instant the requesting D-Bus
# connection closes, so a one-shot `gdbus call ... Inhibit` inhibits for
# microseconds and does nothing. Hold it on a long-lived connection instead: a
# Python helper calls Inhibit then blocks, so the inhibitor lives exactly as
# long as that process. Killing it drops the connection and releases the lock.
inhibit() {
    [ -n "$HOLDER_PID" ] && kill -0 "$HOLDER_PID" 2>/dev/null && return
    python3 - <<'PY' &
import signal
from gi.repository import Gio, GLib
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
bus.call_sync('org.freedesktop.ScreenSaver', '/org/freedesktop/ScreenSaver',
              'org.freedesktop.ScreenSaver', 'Inhibit',
              GLib.Variant('(ss)', ('fullscreen-inhibit', 'Fullscreen application')),
              GLib.VariantType('(u)'), Gio.DBusCallFlags.NONE, -1, None)
signal.signal(signal.SIGTERM, lambda *a: exit(0))
GLib.MainLoop().run()
PY
    HOLDER_PID=$!
}

uninhibit() {
    if [ -n "$HOLDER_PID" ]; then
        kill "$HOLDER_PID" 2>/dev/null
        HOLDER_PID=""
    fi
}

trap uninhibit EXIT TERM INT

# Reconcile every poll (not just on transitions): inhibit() is a no-op when the
# holder is already alive and respawns it if it died, so a crashed holder
# self-heals instead of silently leaving a fullscreen app un-inhibited.
while true; do
    if hyprctl workspaces -j 2>/dev/null | jq -e 'any(.[]; .hasfullscreen // false)' >/dev/null 2>&1; then
        inhibit
    else
        uninhibit
    fi
    sleep 5
done
