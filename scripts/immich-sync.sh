#!/bin/bash
# Runs immich upload every hour in the background

PICTURES="$HOME/Pictures"
IMMICH_BIN="$HOME/.npm-global/bin/immich"

while true; do
    if command -v immich >/dev/null 2>&1; then
        immich upload --recursive "$PICTURES" --ignore "**/ocr/**" \
            >> "$HOME/.cache/immich-sync.log" 2>&1
    elif [[ -x "$IMMICH_BIN" ]]; then
        "$IMMICH_BIN" upload --recursive "$PICTURES" --ignore "**/ocr/**" \
            >> "$HOME/.cache/immich-sync.log" 2>&1
    fi
    sleep 3600
done
