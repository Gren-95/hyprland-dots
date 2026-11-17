#!/bin/bash
# lid.sh — laptop lid switch handler, run by the Lid Switch binds in
# hypr/modules/monitors.lua.
#
# Usage:
#   lid.sh close   lock or suspend (unless docked, per lid-close-action), then
#                  power the panel off
#   lid.sh open    power the panel back on and restore the brightness
#
# logind ignores the lid (HandleLidSwitch=ignore), so closing it never
# suspends or locks by itself. Without the lock here the session would stay
# open until hypridle's lock timeout.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/settings.sh"

readonly INTERNAL_PANEL=eDP-1

# True when a display other than the built-in panel is physically connected.
external_monitor_connected() {
    local status
    for status in /sys/class/drm/card*-*/status; do
        [[ -e $status ]] || continue
        [[ $status =~ -(eDP|LVDS|DSI)-[^/]+/status$ ]] && continue
        [[ $(<"$status") == connected ]] && return 0
    done
    return 1
}

# DPMS rather than "monitor disable": tearing the output down wedges the i915
# atomic page-flip and leaves a black screen on lid open.
panel() {
    hyprctl dispatch "hl.dsp.dpms(\"$1 $INTERNAL_PANEL\")"
}

case "${1:-}" in
    close)
        # Docked, a closed lid is clamshell mode: the session stays in use on
        # the external display, so it must not lock or sleep.
        if ! external_monitor_connected; then
            # lid-close-action from the settings app: lock, suspend or nothing.
            # Suspend locks first through hypridle's before_sleep_cmd.
            case $(valid "$(setting lid-close-action lock)" 'lock|suspend|nothing' lock) in
                lock) loginctl lock-session ;;
                suspend) systemctl suspend ;;
            esac
        fi
        panel off
        ;;
    open)
        panel on && brightnessctl -r
        ;;
    *)
        echo "Usage: lid.sh close|open" >&2
        exit 1
        ;;
esac
