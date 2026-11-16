#!/bin/bash
# Syncs music from Jellyfin to ~/Music/<Artist>/<Album>/<Track>.<ext>
# Jellyfin is the master — files removed from Jellyfin are deleted locally
# Config is saved to ~/.config/jellyfin/sync.conf on first run
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/server.sh"

CONFIG="$JELLYFIN_CONF"
LOG="$JELLYFIN_LOG"

# Give up on a connection that cannot be opened in 10s or that stalls below
# 1 KB/s for 30s, so a server that drops mid-sync cannot hang the run.
CURL_OPTS=(--connect-timeout 10 --speed-limit 1024 --speed-time 30)

# One sync at a time: the cron entry and the systemd timer must not overlap.
# The lock is released when this process exits.
mkdir -p "$CACHE_DIR"
exec 9>"$CACHE_DIR/jellyfin-sync.lock"
if ! flock -n 9; then
    echo "jellyfin-music-sync: another sync is already running" >&2
    exit 0
fi

# --overwrite / --force re-downloads every track even if it already exists
# locally, replacing it with the server's copy. Use after fixing files
# server-side. Normal runs skip tracks that already exist for efficiency.
FORCE=false
for arg in "$@"; do
    case "$arg" in
        --overwrite | --force) FORCE=true ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load or create config
load_config() {
    # Migrate from old config path if it exists and new one doesn't
    local old_config="$HOME/.config/jellyfin-sync.conf"
    if [[ -f "$old_config" && ! -f "$CONFIG" ]]; then
        mkdir -p "$(dirname "$CONFIG")"
        mv "$old_config" "$CONFIG"
        print_info "Migrated config from $old_config to $CONFIG"
    fi

    if [[ -f "$CONFIG" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG"
    fi

    if [[ -z "$JELLYFIN_URL" ]]; then
        while true; do
            read -r -p "Jellyfin server URL (e.g. https://jellyfin.example.com): " JELLYFIN_URL
            [[ -n "$JELLYFIN_URL" ]] && break
            print_warning "URL cannot be empty"
        done
    fi

    if [[ -z "$JELLYFIN_API_KEY" ]]; then
        while true; do
            read -r -p "API key (Jellyfin → Dashboard → API Keys): " JELLYFIN_API_KEY
            [[ -n "$JELLYFIN_API_KEY" ]] && break
            print_warning "API key cannot be empty"
        done
    fi

    cat >"$CONFIG" <<EOF
JELLYFIN_URL="$JELLYFIN_URL"
JELLYFIN_API_KEY="$JELLYFIN_API_KEY"
EOF
    chmod 600 "$CONFIG"
}

# Get the first user's ID from Jellyfin (API keys are not user-scoped)
get_user_id() {
    local user_id
    user_id=$(curl -sf "${CURL_OPTS[@]}" \
        -H "Authorization: MediaBrowser Client=\"jellyfin-sync\", Device=\"jellyfin-sync\", DeviceId=\"jellyfin-sync\", Version=\"1.0\", Token=\"$JELLYFIN_API_KEY\"" \
        "$JELLYFIN_URL/Users" | jq -r '.[0].Id')

    if [[ -z "$user_id" || "$user_id" == "null" ]]; then
        print_error "Could not get user ID — check your URL and API key"
        return 1
    fi

    echo "$user_id"
}

# download_to <url> <file>: fetch with the auth header. Sets HTTP_CODE and
# CURL_RC. A transfer that stalls is cut off by CURL_OPTS: curl then exits
# non-zero while the code still reads 200, so both must be checked.
download_to() {
    HTTP_CODE=$(curl -s "${CURL_OPTS[@]}" -o "$2" -w "%{http_code}" \
        -H "Authorization: MediaBrowser Client=\"jellyfin-sync\", Device=\"jellyfin-sync\", DeviceId=\"jellyfin-sync\", Version=\"1.0\", Token=\"$JELLYFIN_API_KEY\"" \
        "$1")
    CURL_RC=$?
}

# Sanitize a string for use as a filename (max 200 chars to stay under fs limit)
sanitize() {
    echo "$1" | tr -d '/:*?"<>|\\' | sed 's/^ *//;s/ *$//' | cut -c1-200
}

sync_music() {
    # The server is only reachable on the home network. Away from home that is
    # expected, not an error: skip quietly and try again on the next run.
    if ! server_reachable "$JELLYFIN_URL"; then
        print_warning "Jellyfin server unreachable at $JELLYFIN_URL, sync skipped"
        echo "$(date): server unreachable at $JELLYFIN_URL, sync skipped" >>"$LOG"
        return 0
    fi

    local user_id
    if ! user_id=$(get_user_id); then
        notify critical jellyfin-sync dialog-error "Jellyfin Sync Failed" "Could not reach server — check URL and API key"
        return 1
    fi

    print_info "Fetching music library from Jellyfin..."

    local raw_items
    raw_items=$(curl -sf "${CURL_OPTS[@]}" \
        -H "Authorization: MediaBrowser Client=\"jellyfin-sync\", Device=\"jellyfin-sync\", DeviceId=\"jellyfin-sync\", Version=\"1.0\", Token=\"$JELLYFIN_API_KEY\"" \
        "$JELLYFIN_URL/Users/$user_id/Items?Recursive=true&IncludeItemTypes=Audio&Fields=Path,Album,AlbumArtist&Limit=100000")

    if [[ -z "$raw_items" ]]; then
        print_error "No response from Jellyfin — check server URL and API key"
        notify critical jellyfin-sync dialog-error "Jellyfin Sync Failed" "No response from server"
        return 1
    fi

    local total
    total=$(echo "$raw_items" | jq '.TotalRecordCount')

    # Jellyfin is the master, so tracks missing from its list are deleted below.
    # An unreadable reply or an empty library (a server whose media mount is
    # down answers 200 with no items) would delete every local track; stop
    # before that.
    if [[ ! "$total" =~ ^[0-9]+$ || "$total" -eq 0 ]]; then
        print_warning "Server returned no tracks, sync skipped so ~/Music is left untouched"
        echo "$(date): server returned no tracks, sync skipped" >>"$LOG"
        return 0
    fi

    print_info "Found $total tracks on server"

    mkdir -p "$MUSIC_DIR"

    # Build list of expected local paths from server library
    declare -A expected_files
    local downloaded=0 skipped=0 failed=0

    while IFS= read -r item; do
        local id name artist album ext dest_file flat_file server_path

        id=$(echo "$item" | jq -r '.Id')
        name=$(echo "$item" | jq -r '.Name')
        artist=$(echo "$item" | jq -r '.AlbumArtist // "Unknown Artist"')
        album=$(echo "$item" | jq -r '.Album // "Unknown Album"')
        server_path=$(echo "$item" | jq -r '.Path // ""')

        ext="${server_path##*.}"
        [[ -z "$ext" || "$ext" == "$server_path" ]] && ext="mp3"

        # Artist/Album/Track, so tracks that share a name on different albums
        # do not land on the same file.
        dest_file="$MUSIC_DIR/$(sanitize "$artist")/$(sanitize "$album")/$(sanitize "$name").$ext"
        mkdir -p "$(dirname "$dest_file")"

        # Libraries synced before the Artist/Album layout kept every track flat
        # in $MUSIC_DIR. Move such a file into place instead of downloading it
        # again; the first track that claims a flat name takes it.
        flat_file="$MUSIC_DIR/$(sanitize "$name").$ext"
        if [[ ! -f "$dest_file" && -f "$flat_file" ]]; then
            mv "$flat_file" "$dest_file"
        fi

        # Track this file as expected
        expected_files["$dest_file"]=1

        if [[ -f "$dest_file" ]] && [[ "$FORCE" != true ]]; then
            ((skipped++)) || true
            continue
        fi
        if [[ -f "$dest_file" ]]; then
            print_info "Overwriting: $artist — $name"
        else
            print_info "Downloading: $artist — $name"
        fi

        # Download to a temp file and only swap it in on success, so a failed
        # re-download (especially in --overwrite mode) can never clobber the
        # existing good local copy.
        local tmp_file="$dest_file.part"
        download_to "$JELLYFIN_URL/Audio/$id/stream?static=true" "$tmp_file"

        # Fall back: get direct stream URL from PlaybackInfo
        if [[ $CURL_RC -eq 0 && "$HTTP_CODE" == "404" ]]; then
            local stream_url
            stream_url=$(curl -sf "${CURL_OPTS[@]}" \
                -H "Authorization: MediaBrowser Client=\"jellyfin-sync\", Device=\"jellyfin-sync\", DeviceId=\"jellyfin-sync\", Version=\"1.0\", Token=\"$JELLYFIN_API_KEY\"" \
                "$JELLYFIN_URL/Items/$id/PlaybackInfo?UserId=$user_id" |
                jq -r '.MediaSources[0].DirectStreamUrl // empty')

            if [[ -n "$stream_url" ]]; then
                download_to "$JELLYFIN_URL$stream_url" "$tmp_file"
            fi
        fi

        # A curl error means the transfer did not finish: no reply at all
        # (code 000), or a reply cut off by a stall or a dropped connection.
        # Drop the partial file and stop without deleting anything; the next
        # run picks up where this one left off.
        if [[ $CURL_RC -ne 0 ]]; then
            rm -f "$tmp_file"
            print_warning "Lost connection to the server (curl exit $CURL_RC), sync stopped after $downloaded downloaded"
            echo "$(date): connection lost (curl exit $CURL_RC), sync stopped after downloaded=$downloaded" >>"$LOG"
            return 0
        fi

        if [[ "$HTTP_CODE" == "200" ]]; then
            mv -f "$tmp_file" "$dest_file"
            ((downloaded++)) || true
            print_success "Downloaded: $name"
        else
            ((failed++)) || true
            print_warning "Failed [$HTTP_CODE]: $name"
            print_warning "  Server path: $server_path"
            rm -f "$tmp_file"
        fi
    done < <(echo "$raw_items" | jq -c '.Items[]')

    # Remove local files not on the server
    local removed=0
    while IFS= read -r local_file; do
        if [[ -z "${expected_files[$local_file]:-}" ]]; then
            print_warning "Removing (not on server): ${local_file#"$MUSIC_DIR"/}"
            rm -f "$local_file"
            ((removed++)) || true
        fi
    done < <(find "$MUSIC_DIR" -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.ogg" \
        -o -name "*.opus" -o -name "*.m4a" -o -name "*.wav" -o -name "*.aac" \))

    # Clean up empty directories
    find "$MUSIC_DIR" -type d -empty -delete 2>/dev/null || true

    echo ""
    print_success "Sync complete: $downloaded downloaded, $skipped up to date, $removed removed, $failed failed"
    echo "$(date): downloaded=$downloaded skipped=$skipped removed=$removed failed=$failed" >>"$LOG"

    local body="${downloaded} downloaded · ${skipped} up to date · ${removed} removed"
    [[ "$failed" -gt 0 ]] && body+=" · ${failed} failed"
    notify normal jellyfin-sync audio-x-generic "Jellyfin Sync" "$body"
}

if [[ "${1:-}" == "--daemon" ]] && [[ ! -f "$CONFIG" ]]; then
    exit 0
fi

load_config

if [[ "${1:-}" == "--daemon" ]]; then
    while true; do
        sync_music
        sleep 7200
    done
else
    sync_music
fi
