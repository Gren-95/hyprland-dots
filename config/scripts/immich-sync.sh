#!/bin/bash
# Runs immich upload every hour in the background
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"

IMMICH_BIN="$HOME/.npm-global/bin/immich"
LOG_MAX_BYTES=$((1024 * 1024))

# Keep one rotated generation so the log cannot grow without bound.
rotate_log() {
    mkdir -p "$(dirname "$IMMICH_LOG")"
    if [[ -f "$IMMICH_LOG" && "$(stat -c %s "$IMMICH_LOG")" -gt "$LOG_MAX_BYTES" ]]; then
        mv -f "$IMMICH_LOG" "$IMMICH_LOG.1"
    fi
}

run_upload() {
    rotate_log

    local bin=""
    if command -v immich >/dev/null 2>&1; then
        bin="immich"
    elif [[ -x "$IMMICH_BIN" ]]; then
        bin="$IMMICH_BIN"
    else
        return
    fi

    local output exit_code
    output=$("$bin" upload --recursive "$PICTURES_DIR" --ignore "**/{ocr,Screenshots}/**" 2>&1)
    exit_code=$?
    echo "$output" >>"$IMMICH_LOG"

    if [[ "$exit_code" -ne 0 ]]; then
        notify critical immich-sync dialog-error "Immich Sync Failed" "$(echo "$output" | tail -1)"
        return
    fi

    local new_count
    new_count=$(echo "$output" | grep -oP 'Found \K\d+(?= new)' | head -1)

    if [[ -n "$new_count" && "$new_count" -gt 0 ]]; then
        notify normal immich-sync camera-photo "Immich Sync" "Uploaded $new_count new photo(s)"
    fi
}

# --daemon: loop every hour (legacy mode).
# (no args): run once and exit (used by cron entries managed via sync-toggle.sh).
if [[ "${1:-}" == "--daemon" ]]; then
    while true; do
        run_upload
        sleep 3600
    done
else
    run_upload
fi
