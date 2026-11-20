#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/settings.sh"

# The folder set in the settings app (Appearance, Wallpaper folder).
WALLPAPER_DIR=$(setting_dir wallpaper-dir "$WALLPAPER_DIR")

# If a path is given as $1, apply that exact wallpaper. Otherwise pick a
# random one from $WALLPAPER_DIR. awww applies to every output by default and
# animates GIFs natively.
if [[ $# -ge 1 && -f "$1" ]]; then
    wp="$1"
else
    wp=$(find "$WALLPAPER_DIR" -type f | shuf -n 1)
    if [[ -z "$wp" ]]; then
        echo "wallpaper.sh: no wallpapers in $WALLPAPER_DIR" >&2
        exit 1
    fi
fi

awww img "$wp" --transition-type fade
