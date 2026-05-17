#!/bin/bash
# Toggle waybar between floating and docked mode
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"

FLOATING_CONF="$HOME/.config/waybar/config"
DOCKED_CONF="$HOME/.config/waybar/config-docked"
FLOATING_CSS="$HOME/.config/waybar/style.css"
DOCKED_CSS="$HOME/.config/waybar/style-docked.css"
ACTIVE_CONF="$HOME/.config/waybar/config-active"
ACTIVE_CSS="$HOME/.config/waybar/style-active.css"

# Determine current mode from symlink or fallback to floating
if [[ -L "$ACTIVE_CONF" ]] && [[ "$(readlink "$ACTIVE_CONF")" == "$DOCKED_CONF" ]]; then
    ln -sf "$FLOATING_CONF" "$ACTIVE_CONF"
    ln -sf "$FLOATING_CSS" "$ACTIVE_CSS"
    notify normal waybar preferences-desktop "Waybar" "Switched to floating mode"
else
    ln -sf "$DOCKED_CONF" "$ACTIVE_CONF"
    ln -sf "$DOCKED_CSS" "$ACTIVE_CSS"
    notify normal waybar preferences-desktop "Waybar" "Switched to docked mode"
fi

killall waybar
waybar -c "$ACTIVE_CONF" -s "$ACTIVE_CSS" >/dev/null 2>&1 &
