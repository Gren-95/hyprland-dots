#!/bin/bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"

ACTION="${1:-status}"
MODE_FILE="/tmp/waybar-trayscale-mode"
IMMICH_BIN="$HOME/.npm-global/bin/immich"

get_mode() {
    cat "$MODE_FILE" 2>/dev/null || echo "0"
}

immich_bin() {
    if command -v immich >/dev/null 2>&1; then
        echo "immich"
    elif [[ -x "$IMMICH_BIN" ]]; then
        echo "$IMMICH_BIN"
    fi
}

case "$ACTION" in
    scroll-up)
        mode=$(get_mode)
        echo $(( (mode + 1) % 7 )) > "$MODE_FILE"
        pkill -RTMIN+9 waybar
        ;;
    scroll-down)
        mode=$(get_mode)
        echo $(( (mode + 6) % 7 )) > "$MODE_FILE"
        pkill -RTMIN+9 waybar
        ;;
    toggle)
        if tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' > /dev/null 2>&1; then
            tailscale down
        else
            tailscale up
        fi
        pkill -RTMIN+9 waybar
        ;;
    click)
        mode=$(get_mode)
        case "$mode" in
            1)
                bin=$(immich_bin)
                if [[ -n "$bin" ]]; then
                    notify low immich-sync camera-photo "Immich" "Starting sync..."
                    "$bin" upload --recursive "$PICTURES_DIR" --ignore "**/ocr/**" &
                else
                    notify critical immich-sync dialog-error "Immich" "immich CLI not found"
                fi
                ;;
            2)
                notify low jellyfin-sync audio-x-generic "Jellyfin" "Starting sync..."
                bash "$SCRIPTS_DIR/jellyfin-music-sync.sh" &
                ;;
            3)
                swaync-client --toggle-panel --skip-wait
                ;;
            4)
                if pgrep -x hypridle > /dev/null; then
                    pkill hypridle
                    notify low hypridle caffeine-on 'Stay Awake' 'Idle management disabled'
                else
                    hypridle &
                    notify low hypridle caffeine-off 'Sleep Mode' 'Idle management enabled'
                fi
                pkill -RTMIN+9 waybar
                ;;
            5)
                hyprpicker -a
                ;;
            6)
                cliphist list | rofi -dmenu -p Clipboard -theme ~/.config/rofi/clipboard.rasi | cliphist decode | wl-copy
                ;;
            *)
                flatpak run dev.deedles.Trayscale
                ;;
        esac
        ;;
    *)
        mode=$(get_mode)
        case "$mode" in
            1)
                echo '{"text": "󰋩", "tooltip": "Immich — click to sync", "class": "immich"}'
                ;;
            2)
                echo '{"text": "󰝚", "tooltip": "Jellyfin — click to sync", "class": "jellyfin"}'
                ;;
            3)
                if swaync-client --get-dnd 2>/dev/null | grep -q "true"; then
                    echo '{"text": "󰂛", "tooltip": "DND on — click to open panel", "class": "dnd"}'
                else
                    echo '{"text": "󰂚", "tooltip": "Notifications — click to open panel", "class": "notifications"}'
                fi
                ;;
            4)
                if pgrep -x hypridle > /dev/null; then
                    echo '{"text": "󰒳", "tooltip": "Idle: Active — click to disable", "class": "idle-on"}'
                else
                    echo '{"text": "󰒲", "tooltip": "Idle: Disabled — click to enable", "class": "idle-off"}'
                fi
                ;;
            5)
                echo '{"text": "󰈊", "tooltip": "Color picker — click to pick", "class": "colorpicker"}'
                ;;
            6)
                echo '{"text": "󰅍", "tooltip": "Clipboard — click to open", "class": "clipboard"}'
                ;;
            *)
                if tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' > /dev/null 2>&1; then
                    echo '{"text": "󰖂", "tooltip": "Tailscale: Connected — click to manage", "class": "connected"}'
                else
                    echo '{"text": "󰖂", "tooltip": "Tailscale: Disconnected — click to manage", "class": "disconnected"}'
                fi
                ;;
        esac
        ;;
esac
