#!/bin/bash
# Runs immich upload every hour in the background
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

IMMICH_BIN="$HOME/.npm-global/bin/immich"

while true; do
    if command -v immich >/dev/null 2>&1; then
        immich upload --recursive "$PICTURES_DIR" --ignore "**/ocr/**" \
            >> "$IMMICH_LOG" 2>&1
    elif [[ -x "$IMMICH_BIN" ]]; then
        "$IMMICH_BIN" upload --recursive "$PICTURES_DIR" --ignore "**/ocr/**" \
            >> "$IMMICH_LOG" 2>&1
    fi
    sleep 3600
done
