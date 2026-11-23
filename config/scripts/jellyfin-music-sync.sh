#!/bin/bash
# Mirrors the Jellyfin music library into the music folder with jellyfin-music-rs
# (https://github.com/Gren-95/jellyfin-music-rs), from jellyfin-sync.timer or by
# hand. Jellyfin is the master: tracks removed there are deleted here. The tool
# does the sync; this wrapper adds the desktop side: the folder and server
# address from the settings app, the log, notifications, and asking for a login
# when run in a terminal without one.
#   --overwrite, --force   download every track and cover again
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/settings.sh"

# The music folder and server address can be set in the settings app (Sync).
# The login (URL and API key) is jellyfin-music-rs's, kept in $JELLYFIN_CONF;
# JELLYFIN_API_KEY in the environment wins over the file's key.
MUSIC_DIR=$(setting_dir jellyfin-folder "$MUSIC_DIR")
URL_SETTING=$(valid "$(setting jellyfin-url "")" 'https?://[^[:space:]]+' "")

# Where `dots.sh setup` installs jellyfin-music-rs; the timer's PATH may not
# include ~/.local/bin.
JELLYFIN_BIN="$HOME/.local/bin/jellyfin-music-rs"
LOG_MAX_BYTES=$((1024 * 1024))

# Keep one rotated generation so the log cannot grow without bound.
rotate_log() {
    mkdir -p "$(dirname "$JELLYFIN_LOG")"
    if [[ -f "$JELLYFIN_LOG" && "$(stat -c %s "$JELLYFIN_LOG")" -gt "$LOG_MAX_BYTES" ]]; then
        mv -f "$JELLYFIN_LOG" "$JELLYFIN_LOG.1"
    fi
}

log_line() {
    echo "$(date): $1" >>"$JELLYFIN_LOG"
}

# Asks for the server and key in a terminal; `login` checks them against the
# server before saving them to $JELLYFIN_CONF.
login_interactively() {
    local url key
    read -r -p "Jellyfin server URL (e.g. https://jellyfin.example.com): " url
    read -r -s -p "API key (Jellyfin → Dashboard → API Keys): " key
    echo
    [[ -n "$url" && -n "$key" ]] || return 1
    "$JELLYFIN_BIN" --config "$JELLYFIN_CONF" login "$url" "$key"
}

# "3 downloaded · 1 removed", leaving out the counts that are 0.
summary() {
    jq -r '[
        (.downloaded | select(. > 0) | "\(.) downloaded"),
        (.updated | select(. > 0) | "\(.) updated"),
        (.removed | select(. > 0) | "\(.) removed"),
        (.failed | length | select(. > 0) | "\(.) failed")
    ] | join(" · ")' <<<"$1"
}

# run_sync [--overwrite]: one sync; its JSON summary decides what to report.
run_sync() {
    local args=(sync --config "$JELLYFIN_CONF" --dir "$MUSIC_DIR" --json "$@")
    [[ -n "$URL_SETTING" ]] && args+=(--url "$URL_SETTING")

    # In a terminal the progress bars go to the screen; otherwise the tool's
    # per-track lines go to the log.
    local json
    if [[ -t 2 ]]; then
        json=$("$JELLYFIN_BIN" "${args[@]}")
    else
        json=$("$JELLYFIN_BIN" "${args[@]}" 2>>"$JELLYFIN_LOG")
    fi

    local status message body
    # No JSON at all (the tool crashed) counts as an error.
    status=$(jq -r '.status // empty' <<<"$json" 2>/dev/null)
    status=${status:-error}
    message=$(jq -r '.message // empty' <<<"$json" 2>/dev/null)
    case "$status" in
        ok)
            body=$(summary "$json")
            log_line "sync complete${body:+: $body}"
            [[ -n "$body" ]] && notify normal jellyfin-sync audio-x-generic "Jellyfin Sync" "$body"
            return 0
            ;;
        not_configured)
            # From the timer there is nobody to ask; the unit only starts once
            # the config file exists, so this is a key that was removed.
            if [[ -t 0 ]] && login_interactively; then
                run_sync "$@"
                return
            fi
            log_line "not logged in, sync skipped"
            return 0
            ;;
        unreachable | already_running | empty_library | connection_lost | interrupted)
            # Away from home, a second run, a server whose media is not
            # mounted, or a dropped connection: nothing was deleted and the
            # next run picks up from here.
            log_line "sync skipped ($status): $message"
            [[ -t 1 ]] && echo "Jellyfin sync skipped: $message"
            return 0
            ;;
        *)
            # error, too_many_deletions: something to look at.
            log_line "sync failed ($status): ${message:-no summary from jellyfin-music-rs}"
            notify critical jellyfin-sync dialog-error "Jellyfin Sync Failed" "${message:-jellyfin-music-rs gave no summary, see $JELLYFIN_LOG}"
            return 1
            ;;
    esac
}

rotate_log
if [[ ! -x "$JELLYFIN_BIN" ]]; then
    log_line "jellyfin-music-rs not found at $JELLYFIN_BIN, sync skipped"
    notify normal jellyfin-sync dialog-warning "Jellyfin sync skipped" "jellyfin-music-rs is not installed. Run dots.sh setup to install it."
    exit 0
fi

extra=()
for arg in "$@"; do
    case "$arg" in
        --overwrite | --force) extra=(--overwrite) ;;
    esac
done
run_sync "${extra[@]}"
