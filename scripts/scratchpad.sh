#!/bin/bash
# scratchpad.sh - Toggle a drop-down kitty on the Hyprland special workspace
# "scratchpad". Spawns it on first use.
#
# Usage: scratchpad.sh
#
# Hyprland's Lua config takes Lua expressions in `hyprctl dispatch`.
#   hl.dsp.workspace.toggle_special("name")   - taken from Hyprland's example config
#   hl.dsp.window.move({ workspace = "special:name", window = "address:0x..." })
#                                              - `workspace` is documented; the
#                                                `window` selector key is unverified
# For a floating, sized drop-down add a window_rule in hypr/modules/rules.lua
# matching class "scratchpad".
set -euo pipefail

CLASS="scratchpad"
SPECIAL="scratchpad"
SPAWN_TIMEOUT_DS=30   # deciseconds

window_address() {
    hyprctl clients -j | jq -r --arg c "$CLASS" 'first(.[] | select(.class == $c) | .address) // empty'
}

toggle_special() {
    hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$SPECIAL\")" >/dev/null
}

addr=$(window_address)

if [[ -n "$addr" ]]; then
    toggle_special
    exit 0
fi

setsid -f kitty --class "$CLASS" >/dev/null 2>&1

for (( i = 0; i < SPAWN_TIMEOUT_DS; i++ )); do
    addr=$(window_address)
    [[ -n "$addr" ]] && break
    sleep 0.1
done

if [[ -z "$addr" ]]; then
    echo "scratchpad.sh: kitty window did not appear" >&2
    exit 1
fi

# Park the new window on the special workspace, then show that workspace.
hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:$SPECIAL\", window = \"address:$addr\" })" >/dev/null
toggle_special
