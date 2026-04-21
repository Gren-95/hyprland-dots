#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

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
        echo $(( (mode + 1) % 3 )) > "$MODE_FILE"
        pkill -RTMIN+9 waybar
        ;;
    scroll-down)
        mode=$(get_mode)
        echo $(( (mode + 2) % 3 )) > "$MODE_FILE"
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
                    notify-send -u low -i camera-photo "Immich" "Starting sync..."
                    "$bin" upload --recursive "$PICTURES_DIR" --ignore "**/ocr/**" &
                else
                    notify-send -u critical "Immich" "immich CLI not found"
                fi
                ;;
            2)
                notify-send -u low -i audio-x-generic "Jellyfin" "Starting sync..."
                bash "$SCRIPTS_DIR/jellyfin-music-sync.sh" &
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
