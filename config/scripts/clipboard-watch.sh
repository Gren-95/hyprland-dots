#!/bin/bash
# clipboard-watch.sh — (re)start the clipboard history watcher.
#
# Usage: clipboard-watch.sh restart
#
# wl-paste hands every copy to `cliphist store`, which keeps the newest
# clipboard-max-items entries (Privacy in the settings app; default 750).
# restart.sh starts it with the session; the settings app runs it again when
# the length changes, since cliphist reads the limit only at start.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/settings.sh"

[[ ${1:-} == restart ]] || {
    echo "usage: clipboard-watch.sh restart" >&2
    exit 2
}
command -v cliphist >/dev/null || {
    echo "clipboard-watch: cliphist is not installed" >&2
    exit 1
}

MAX=$(valid "$(setting clipboard-max-items 750)" '[0-9]{2,4}' 750)
pkill -f "wl-paste --watch cliphist" 2>/dev/null
setsid -f wl-paste --watch cliphist -max-items "$MAX" store >/dev/null 2>&1
