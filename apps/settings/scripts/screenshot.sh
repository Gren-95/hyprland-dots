#!/bin/bash
# screenshot.sh - Screenshot one panel of the settings app, to check the UI.
#
# Usage: screenshot.sh <panel> <out.png> [height] [scroll]
#   Starts the debug build (target/debug/settings) on <panel>, floats it at
#   1100 x <height> (default 1000), moves it <scroll> px above the top of the
#   screen so lower parts of a long panel show (default 0), saves the panel
#   (without the sidebar) to <out.png> and closes the window again. Only the
#   window it started is touched, found by its process id.
set -euo pipefail

[[ $# -ge 2 ]] || {
    echo "usage: $0 <panel> <out.png> [height] [scroll]" >&2
    exit 2
}
panel=$1 out=$2 height=${3:-1000} scroll=${4:-0}
app="$(dirname "${BASH_SOURCE[0]}")/../target/debug/settings"
SIDEBAR=232
TOP=30

"$app" -p "$panel" >/dev/null 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT

# Wait for the window to map.
addr=""
for _ in $(seq 40); do
    addr=$(hyprctl clients -j | jq -r --argjson p "$pid" '.[] | select(.pid == $p) | .address')
    [[ -n "$addr" ]] && break
    sleep 0.1
done
[[ -n "$addr" ]] || {
    echo "screenshot.sh: the window did not appear" >&2
    exit 1
}
win="window = \"address:$addr\""
hyprctl dispatch "hl.dsp.window.float({ action = \"enable\", $win })" >/dev/null
hyprctl dispatch "hl.dsp.window.resize({ x = 1100, y = $height, $win })" >/dev/null
hyprctl dispatch "hl.dsp.window.move({ x = 40, y = $((TOP - scroll)), $win })" >/dev/null
# Let it lay out and load what the panel reads from the system.
sleep 2.5
screen_height=$(hyprctl monitors -j | jq '.[0].height')
shown=$((height - scroll))
((shown > screen_height - TOP)) && shown=$((screen_height - TOP))
grim -g "$((40 + SIDEBAR)),$TOP $((1100 - SIDEBAR))x$shown" "$out"
