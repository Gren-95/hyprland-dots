#!/bin/bash
# autostart-apps.sh - Start the apps in ~/.config/autostart once per login.
#
# Usage: autostart-apps.sh
#   restart.sh runs this; it does nothing after the first time in a session
#   (a marker in $XDG_RUNTIME_DIR, which logout clears), so restarting the
#   shell does not start the apps a second time.
#
# Follows the XDG autostart rules for the user's own entries: an entry is
# skipped when Hidden=true, X-GNOME-Autostart-enabled=false, OnlyShowIn does
# not name Hyprland, NotShowIn does, or its TryExec is not installed. The
# settings app (Services > Apps at login) adds, switches and removes entries.
# System-wide entries in /etc/xdg/autostart are not started: this setup
# starts what it needs itself (restart.sh).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
MARKER="$RUNTIME_DIR/autostart-apps.done"
DESKTOP=Hyprland

[[ -e "$MARKER" ]] && exit 0
: >"$MARKER"
[[ -d "$DIR" ]] || exit 0

# The value of a key in the [Desktop Entry] group.
entry_value() {
    sed -n '/^\[Desktop Entry\]/,/^\[/{s/^'"$1"'=//p}' "$2" | head -n1
}

listed() { [[ ";$1;" == *";$DESKTOP;"* ]]; }

for file in "$DIR"/*.desktop; do
    [[ -f "$file" ]] || continue
    [[ $(entry_value Hidden "$file") == true ]] && continue
    [[ $(entry_value X-GNOME-Autostart-enabled "$file") == false ]] && continue
    only=$(entry_value OnlyShowIn "$file")
    [[ -n "$only" ]] && ! listed "$only" && continue
    listed "$(entry_value NotShowIn "$file")" && continue
    try=$(entry_value TryExec "$file")
    [[ -n "$try" ]] && ! command -v "$try" >/dev/null 2>&1 && continue
    setsid -f gio launch "$file" >/dev/null 2>&1 || true
done
