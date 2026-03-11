#!/bin/bash
# Syncs music from Jellyfin to ~/Music
# Jellyfin is the master — files removed from Jellyfin are deleted locally
# Config is saved to ~/.config/jellyfin-sync.conf on first run

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

# Sanitize a string for use as a filename
sanitize() {
    echo "$1" | tr -d '/:*?"<>|\\' | sed 's/^ *//;s/ *$//'
}

sync_music() {
    local user_id
    user_id=$(get_user_id)

    print_info "Fetching music library from Jellyfin..."

    local raw_items
    raw_items=$(curl -sf \
        -H "X-Emby-Token: $JELLYFIN_API_KEY" \
        "$JELLYFIN_URL/Users/$user_id/Items?Recursive=true&IncludeItemTypes=Audio&Fields=Path,Album,AlbumArtist&Limit=100000")

    if [[ -z "$raw_items" ]]; then
        print_error "No response from Jellyfin — check server URL and API key"
        exit 1
    fi

    local total
    total=$(echo "$raw_items" | jq '.TotalRecordCount')
    print_info "Found $total tracks on server"

    mkdir -p "$MUSIC_DIR"

    # Build list of expected local paths from server library
    declare -A expected_files
    local downloaded=0 skipped=0 failed=0

    while IFS= read -r item; do
        local id name artist album ext dest_dir dest_file server_path

        id=$(echo "$item"     | jq -r '.Id')
        name=$(echo "$item"   | jq -r '.Name')
        artist=$(echo "$item" | jq -r '.AlbumArtist // "Unknown Artist"')
        album=$(echo "$item"  | jq -r '.Album // "Unknown Album"')
        server_path=$(echo "$item" | jq -r '.Path // ""')

        ext="${server_path##*.}"
        [[ -z "$ext" || "$ext" == "$server_path" ]] && ext="mp3"

        dest_dir="$MUSIC_DIR/$(sanitize "$artist")/$(sanitize "$album")"
        dest_file="$dest_dir/$(sanitize "$name").$ext"

        # Track this file as expected
        expected_files["$dest_file"]=1

        if [[ -f "$dest_file" ]]; then
            ((skipped++)) || true
            continue
        fi

        mkdir -p "$dest_dir"
        print_info "Downloading: $artist — $name"

        if curl -sf \
            -H "X-Emby-Token: $JELLYFIN_API_KEY" \
            "$JELLYFIN_URL/Audio/$id/stream?static=true" \
            -o "$dest_file"; then
            ((downloaded++)) || true
            print_success "Downloaded: $artist — $name"
        else
            ((failed++)) || true
            print_warning "Failed: $artist — $name"
            rm -f "$dest_file"
        fi
    done < <(echo "$raw_items" | jq -c '.Items[]')

    # Remove local files not on the server
    local removed=0
    while IFS= read -r local_file; do
        if [[ -z "${expected_files[$local_file]}" ]]; then
            print_warning "Removing (not on server): ${local_file#$MUSIC_DIR/}"
            rm -f "$local_file"
            ((removed++)) || true
        fi
    done < <(find "$MUSIC_DIR" -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.ogg" \
        -o -name "*.opus" -o -name "*.m4a" -o -name "*.wav" -o -name "*.aac" \))

    # Clean up empty directories
    find "$MUSIC_DIR" -type d -empty -delete 2>/dev/null || true

    echo ""
    print_success "Sync complete: $downloaded downloaded, $skipped up to date, $removed removed, $failed failed"
    echo "$(date): downloaded=$downloaded skipped=$skipped removed=$removed failed=$failed" >> "$LOG"
}

load_config
sync_music
