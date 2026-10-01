#!/bin/bash
set -euo pipefail

WALLPAPER_DIR="$HOME/Pictures/wallpapers"

# If a path is given as $1, apply that exact wallpaper. Otherwise pick a
# random one from $WALLPAPER_DIR. awww applies to every output by default and
# animates GIFs natively.
if [[ $# -ge 1 && -f "$1" ]]; then
    wp="$1"
else
    wp=$(find "$WALLPAPER_DIR" -type f | shuf -n 1)
fi

awww img "$wp" --transition-type fade
