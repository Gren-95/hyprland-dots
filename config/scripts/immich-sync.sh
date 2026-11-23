#!/bin/bash
# Runs immich upload every hour in the background
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/server.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/settings.sh"

# The folder uploaded (Sync in the settings app). The server and key are the
# immich-rs login (`immich-rs login <url> <key>`), never the app's.
UPLOAD_DIR=$(setting_dir immich-folder "$PICTURES_DIR")

# Where `dots.sh setup` installs immich-rs. Cron runs with PATH=/usr/bin:/bin,
# so the full path is used rather than a PATH lookup.
IMMICH_BIN="$HOME/.local/bin/immich-rs"
LOG_MAX_BYTES=$((1024 * 1024))

# Keep one rotated generation so the log cannot grow without bound.
rotate_log() {
    mkdir -p "$(dirname "$IMMICH_LOG")"
    if [[ -f "$IMMICH_LOG" && "$(stat -c %s "$IMMICH_LOG")" -gt "$LOG_MAX_BYTES" ]]; then
        mv -f "$IMMICH_LOG" "$IMMICH_LOG.1"
    fi
}

# One line for the failure notification. immich-rs prints what failed first on
# stderr ("Failed to connect to server <url>: 401"); an API error follows it as
# JSON whose "message" says why ("Invalid API key").
failure_summary() {
    local errors=$1 exit_code=$2 what reason
    what=$(head -1 <<<"$errors")
    reason=$(grep -oPm1 '"message": "\K[^"]+' <<<"$errors")
    if [[ -z "$what" ]]; then
        echo "immich-rs exited with code $exit_code"
    else
        echo "$what${reason:+ ($reason)}"
    fi
}

run_upload() {
    rotate_log

    if [[ ! -x "$IMMICH_BIN" ]]; then
        echo "$(date): immich-rs not found at $IMMICH_BIN, upload skipped" >>"$IMMICH_LOG"
        # Same key every run, so an hourly cron replaces the notification
        # instead of stacking a new one.
        notify normal immich-sync dialog-warning "Immich sync skipped" "immich-rs is not installed. Run dots.sh setup to install it."
        return 0
    fi

    # The server is only reachable on the home network. Away from home that is
    # expected, not an error: log it and try again on the next run, without a
    # critical notification every hour. A missing URL means the CLI is not logged
    # in, which the upload below reports.
    local url
    url=$(sed -n 's/^url: *//p' "$IMMICH_AUTH" 2>/dev/null)
    if [[ -n "$url" ]] && ! server_reachable "$url/server/ping"; then
        echo "$(date): server unreachable at $url, upload skipped" >>"$IMMICH_LOG"
        [[ -t 1 ]] && echo "Immich server unreachable at $url, upload skipped"
        return 0
    fi

    # stderr apart from stdout, so the notification shows the error itself
    # rather than the progress lines before it.
    local output errors exit_code err_file
    err_file=$(mktemp)
    output=$("$IMMICH_BIN" upload --recursive "$UPLOAD_DIR" --ignore "**/{ocr,Screenshots}/**" 2>"$err_file")
    exit_code=$?
    errors=$(<"$err_file")
    rm -f "$err_file"
    [[ -n "$output" ]] && echo "$output" >>"$IMMICH_LOG"
    [[ -n "$errors" ]] && echo "$errors" >>"$IMMICH_LOG"

    if [[ "$exit_code" -ne 0 ]]; then
        notify critical immich-sync dialog-error "Immich Sync Failed" "$(failure_summary "$errors" "$exit_code")"
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
