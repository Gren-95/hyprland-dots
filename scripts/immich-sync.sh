#!/bin/bash
# Runs immich upload every hour in the background
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

IMMICH_BIN="$HOME/.npm-global/bin/immich"

run_upload() {
    local bin=""
    if command -v immich >/dev/null 2>&1; then
        bin="immich"
    elif [[ -x "$IMMICH_BIN" ]]; then
        bin="$IMMICH_BIN"
    else
        return
    fi

    local output
    output=$("$bin" upload --recursive "$PICTURES_DIR" --ignore "**/ocr/**" 2>&1)
    echo "$output" >> "$IMMICH_LOG"

    local new_count
    new_count=$(echo "$output" | grep -oP 'Found \K\d+(?= new)' | head -1)

    if [[ -n "$new_count" && "$new_count" -gt 0 ]]; then
        notify-send -u normal -i camera-photo "Immich Sync" "Uploaded $new_count new photo(s)"
    fi
}

while true; do
    run_upload
    sleep 3600
done
