#!/bin/bash
# inhibit.sh — hold an org.freedesktop.ScreenSaver idle inhibitor.
#
# A ScreenSaver inhibitor is bound to the D-Bus connection that requested it and
# is released the instant that connection closes, so a one-shot `gdbus call ...
# Inhibit` inhibits for microseconds and is useless. Instead a small Python
# helper calls Inhibit and then blocks in a main loop: the inhibitor lives
# exactly as long as that process. Killing it drops the connection and releases
# the lock. While nobody provides ScreenSaver (hypridle stopped by Stay
# Awake) it waits quietly and registers once hypridle is back.
#
# Source from another script:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/inhibit.sh"
#
# Usage:
#   inhibit_start <app-name> <reason>   # no-op when a holder is already alive
#   inhibit_stop                        # release the inhibitor
#
# State lives in INHIBIT_HOLDER_PID; callers that exit right after
# inhibit_start (idle-inhibit-toggle.sh) read it to record a pidfile.

INHIBIT_HOLDER_PID=""

inhibit_start() {
    local app=$1 reason=$2
    if [[ -n "$INHIBIT_HOLDER_PID" ]] && kill -0 "$INHIBIT_HOLDER_PID" 2>/dev/null; then
        return 0
    fi
    python3 - "$app" "$reason" <<'PY' &
import signal
import sys
from gi.repository import Gio, GLib

app, reason = sys.argv[1], sys.argv[2]
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)


def inhibit():
    """Register; False (try again) while nobody provides ScreenSaver."""
    try:
        bus.call_sync('org.freedesktop.ScreenSaver', '/org/freedesktop/ScreenSaver',
                      'org.freedesktop.ScreenSaver', 'Inhibit',
                      GLib.Variant('(ss)', (app, reason)),
                      GLib.VariantType('(u)'), Gio.DBusCallFlags.NONE, -1, None)
        return False
    except GLib.Error:
        return True


signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
# hypridle provides ScreenSaver, and Stay Awake stops it: then nothing can
# put the machine to sleep, so there is nothing to hold yet. Keep trying,
# so the hold is in place as soon as hypridle is back.
if inhibit():
    GLib.timeout_add_seconds(5, inhibit)
GLib.MainLoop().run()
PY
    INHIBIT_HOLDER_PID=$!
}

inhibit_stop() {
    if [[ -n "$INHIBIT_HOLDER_PID" ]]; then
        kill "$INHIBIT_HOLDER_PID" 2>/dev/null || true
        INHIBIT_HOLDER_PID=""
    fi
}
