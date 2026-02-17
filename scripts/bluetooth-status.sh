#!/bin/bash
# Bluetooth status script for waybar
# Shows connected device count, scrolling cycles through devices

INDEX_FILE="/tmp/bt-scroll-index"

# Get all connected device names
mapfile -t DEVICES < <(bluetoothctl devices Connected 2>/dev/null | sed 's/Device [0-9A-F:]*[[:space:]]*//')
COUNT=${#DEVICES[@]}

case "$1" in
    scroll-up)
        idx=$(cat "$INDEX_FILE" 2>/dev/null || echo "0")
        idx=$(( (idx + 1) % (COUNT + 1) ))
        echo "$idx" > "$INDEX_FILE"
        pkill -RTMIN+8 waybar
        exit 0
        ;;
    scroll-down)
        idx=$(cat "$INDEX_FILE" 2>/dev/null || echo "0")
        idx=$(( (idx - 1 + COUNT + 1) % (COUNT + 1) ))
        echo "$idx" > "$INDEX_FILE"
        pkill -RTMIN+8 waybar
        exit 0
        ;;
esac

if [[ $COUNT -eq 0 ]]; then
    echo '{"text": "󰂲", "tooltip": "No devices connected", "class": "disconnected"}'
    exit 0
fi

idx=$(cat "$INDEX_FILE" 2>/dev/null || echo "0")

# Clamp idx in case devices disconnected
if [[ $idx -gt $COUNT ]]; then
    idx=0
    echo "0" > "$INDEX_FILE"
fi

tooltip=$(printf '%s\n' "${DEVICES[@]}" | tr '\n' '|' | sed 's/|$//' | sed 's/|/\\n/g')

if [[ $idx -eq 0 ]]; then
    echo "{\"text\": \"󰂰 $COUNT\", \"tooltip\": \"$tooltip\", \"class\": \"connected\"}"
else
    device="${DEVICES[$((idx - 1))]}"
    echo "{\"text\": \"󰂰 $device\", \"tooltip\": \"$tooltip\", \"class\": \"connected\"}"
fi
