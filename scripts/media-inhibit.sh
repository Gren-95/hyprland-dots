#!/bin/bash
# media-inhibit.sh - Inhibit idle actions (dim/lock/dpms/suspend) while media
# is playing, via the org.freedesktop.ScreenSaver interface that hypridle owns.
#
# IMPORTANT: a ScreenSaver inhibitor is bound to the D-Bus connection that
# requested it and is released the instant that connection closes. A one-shot
# `gdbus call ... Inhibit` therefore inhibits for microseconds and is useless
# (this was the long-standing bug). Instead we hold the inhibitor on a
# long-lived connection: a small Python helper calls Inhibit and then blocks in
# a main loop, so the inhibitor lives exactly as long as that process. Stopping
# playback kills the helper, which drops the connection and releases the lock.
set -uo pipefail

HOLDER_PID=""

# Start a persistent inhibitor if one isn't already held.
inhibit() {
    [ -n "$HOLDER_PID" ] && kill -0 "$HOLDER_PID" 2>/dev/null && return
    python3 - <<'PY' &
import signal
from gi.repository import Gio, GLib
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
bus.call_sync('org.freedesktop.ScreenSaver', '/org/freedesktop/ScreenSaver',
              'org.freedesktop.ScreenSaver', 'Inhibit',
              GLib.Variant('(ss)', ('media-inhibit', 'Media is playing')),
              GLib.VariantType('(u)'), Gio.DBusCallFlags.NONE, -1, None)
signal.signal(signal.SIGTERM, lambda *a: exit(0))
GLib.MainLoop().run()
PY
    HOLDER_PID=$!
}

# Release the inhibitor by dropping the holder's connection.
uninhibit() {
    if [ -n "$HOLDER_PID" ]; then
        kill "$HOLDER_PID" 2>/dev/null
        HOLDER_PID=""
    fi
}

trap uninhibit EXIT TERM INT

# Reconcile every poll rather than only on play/pause transitions: inhibit() is
# a no-op when the holder is already alive and respawns it if it died, so a
# crashed holder self-heals instead of silently leaving media un-inhibited.
while true; do
    if [ "$(playerctl status 2>/dev/null)" = "Playing" ]; then
        inhibit
    else
        uninhibit
    fi
    sleep 3
done
