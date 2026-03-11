#!/bin/bash
# Syncs music from Jellyfin to ~/Music
# Config is saved to ~/.config/jellyfin-sync.conf on first run

set -e

CONFIG="$HOME/.config/jellyfin-sync.conf"
MUSIC_DIR="$HOME/Music"
LOG="$HOME/.cache/jellyfin-sync.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Load or create config
load_config() {
    if [[ -f "$CONFIG" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG"
    fi

    if [[ -z "$JELLYFIN_URL" ]]; then
        while true; do
            read -p "Jellyfin server URL (e.g. https://jellyfin.example.com): " JELLYFIN_URL
            [[ -n "$JELLYFIN_URL" ]] && break
            print_warning "URL cannot be empty"
        done
    fi

    if [[ -z "$JELLYFIN_API_KEY" ]]; then
        while true; do
            read -p "API key (Jellyfin → Dashboard → API Keys): " JELLYFIN_API_KEY
            [[ -n "$JELLYFIN_API_KEY" ]] && break
            print_warning "API key cannot be empty"
        done
    fi

    # Save config
    cat > "$CONFIG" <<EOF
JELLYFIN_URL="$JELLYFIN_URL"
JELLYFIN_API_KEY="$JELLYFIN_API_KEY"
EOF
    chmod 600 "$CONFIG"
}

# Get the current user's ID from Jellyfin
get_user_id() {
    local user_id
    user_id=$(curl -sf \
        -H "X-Emby-Token: $JELLYFIN_API_KEY" \
        "$JELLYFIN_URL/Users/Me" | jq -r '.Id')

    if [[ -z "$user_id" || "$user_id" == "null" ]]; then
        print_error "Could not get user ID — check your URL and API key"
        exit 1
    fi

    echo "$user_id"
}

# Fetch all audio items from Jellyfin
get_music_items() {
    local user_id="$1"
    curl -sf \
        -H "X-Emby-Token: $JELLYFIN_API_KEY" \
        "$JELLYFIN_URL/Users/$user_id/Items?Recursive=true&IncludeItemTypes=Audio&Fields=Path,Album,AlbumArtist&Limit=100000" \
        | jq -c '.Items[]'
}

# Sanitize a string for use as a filename
sanitize() {
    echo "$1" | tr -d '/:*?"<>|\\' | sed 's/^ *//;s/ *$//'
}

# Sync all music
sync_music() {
    local user_id
    user_id=$(get_user_id)
    print_info "Fetching music library from Jellyfin..."

    local items
    items=$(get_music_items "$user_id")

    local total downloaded skipped failed
    total=$(echo "$items" | wc -l)
    downloaded=0
    skipped=0
    failed=0

    print_info "Found $total tracks — syncing to $MUSIC_DIR"
    mkdir -p "$MUSIC_DIR"

    while IFS= read -r item; do
        local id name artist album ext dest_dir dest_file

        id=$(echo "$item" | jq -r '.Id')
        name=$(echo "$item" | jq -r '.Name')
        artist=$(echo "$item" | jq -r '.AlbumArtist // "Unknown Artist"')
        album=$(echo "$item" | jq -r '.Album // "Unknown Album"')

        # Get file extension from the server path
        local server_path
        server_path=$(echo "$item" | jq -r '.Path // ""')
        ext="${server_path##*.}"
        [[ -z "$ext" || "$ext" == "$server_path" ]] && ext="mp3"

        dest_dir="$MUSIC_DIR/$(sanitize "$artist")/$(sanitize "$album")"
        dest_file="$dest_dir/$(sanitize "$name").$ext"

        if [[ -f "$dest_file" ]]; then
            ((skipped++)) || true
            continue
        fi

        mkdir -p "$dest_dir"

        if curl -sf \
            -H "X-Emby-Token: $JELLYFIN_API_KEY" \
            "$JELLYFIN_URL/Audio/$id/stream?static=true" \
            -o "$dest_file" 2>>"$LOG"; then
            ((downloaded++)) || true
            print_success "Downloaded: $artist — $name"
        else
            ((failed++)) || true
            print_warning "Failed: $artist — $name"
            rm -f "$dest_file"
        fi
    done <<< "$items"

    echo ""
    print_success "Sync complete: $downloaded downloaded, $skipped already present, $failed failed"
    echo "$(date): $downloaded downloaded, $skipped skipped, $failed failed" >> "$LOG"
}

load_config
sync_music
