#!/bin/bash
# idle-inhibit-hold.sh - Hold an org.freedesktop.ScreenSaver idle inhibitor
# until terminated. Started and stopped by Quickshell's IdleService while media
# plays or a window is fullscreen; hypridle stays running, so its lock-before-
# sleep still works.
#
# Usage: idle-inhibit-hold.sh <app-name> <reason>
#
# A ScreenSaver inhibitor lives exactly as long as the D-Bus connection that
# asked for it (see lib/inhibit.sh). This script becomes that process (exec),
# and asks the kernel to send it SIGTERM when its parent dies, so even a killed
# Quickshell cannot leave idle blocked.
exec python3 - "${1:-idle-service}" "${2:-Idle inhibit}" <<'PY'
import ctypes
import signal
import sys
from gi.repository import Gio, GLib

PR_SET_PDEATHSIG = 1
ctypes.CDLL(None).prctl(PR_SET_PDEATHSIG, signal.SIGTERM)

app, reason = sys.argv[1], sys.argv[2]
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
bus.call_sync('org.freedesktop.ScreenSaver', '/org/freedesktop/ScreenSaver',
              'org.freedesktop.ScreenSaver', 'Inhibit',
              GLib.Variant('(ss)', (app, reason)),
              GLib.VariantType('(u)'), Gio.DBusCallFlags.NONE, -1, None)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
GLib.MainLoop().run()
PY
