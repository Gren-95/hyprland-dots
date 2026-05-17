#!/bin/bash
# notify.sh — standardized wrapper around notify-send.
#
# Source from another script:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"
# Or with an absolute path:
#   source ~/.config/scripts/lib/notify.sh
#
# Usage:
#   notify <urgency> <key> <icon> <title> <body> [timeout_ms]
#
#   urgency:    low | normal | critical
#   key:        replace-key — notifications sharing a key replace each other
#               instead of stacking (pass "" to opt out)
#   icon:       freedesktop icon name or absolute path (pass "" to omit)
#   title:      notification title
#   body:       notification body
#   timeout_ms: optional, milliseconds (omit for daemon default)
#
# Always sets -a "hyprland-dots" so all notifications share an app identity.

notify() {
    local urgency=$1 key=$2 icon=$3 title=$4 body=$5 timeout=${6:-}
    local args=(-a "hyprland-dots" -u "$urgency")
    [[ -n "$key" ]]     && args+=(-h "string:x-canonical-private-synchronous:$key")
    [[ -n "$icon" ]]    && args+=(-i "$icon")
    [[ -n "$timeout" ]] && args+=(-t "$timeout")
    notify-send "${args[@]}" "$title" "$body"
}
