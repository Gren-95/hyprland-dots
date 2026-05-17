#!/bin/bash
# Canonical path definitions — source this file to get consistent absolute paths
#
# Usage in other scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
#   or:
#   source ~/.config/scripts/paths.sh

# User directories
PICTURES_DIR="$HOME/Pictures"
WALLPAPER_DIR="$HOME/Pictures/wallpapers"
SCREENSHOTS_DIR="$HOME/Pictures/Screenshots"
OCR_DIR="$HOME/Pictures/Screenshots/ocr"
RECORDINGS_DIR="$HOME/Videos/Recordings"
MUSIC_DIR="$HOME/Music"

# Config directories
CONFIG_DIR="$HOME/.config"
SCRIPTS_DIR="$HOME/.config/scripts"
HYPR_DIR="$HOME/.config/hypr"

# Cache / runtime
CACHE_DIR="$HOME/.cache"
HYPRPAPER_CACHE="$HOME/.cache/hyprpaper.conf"
LOCK_ART="/tmp/hyprlock-art.jpg"
LOCK_BG="$HOME/.config/hypr/lockbg"
SCREENRECORD_PID="/tmp/screenrecord.pid"

# Logs
IMMICH_LOG="$HOME/.cache/immich-sync.log"
JELLYFIN_LOG="$HOME/.cache/jellyfin-sync.log"

# External tool configs
JELLYFIN_CONF="$HOME/.config/jellyfin/sync.conf"
