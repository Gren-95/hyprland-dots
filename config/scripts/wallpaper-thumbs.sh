#!/bin/bash
# Card thumbnails for the wallpaper deck (quickshell/WallpaperDeck.qml).
#
# Usage: wallpaper-thumbs.sh <file>...
#
# Makes a small portrait JPEG for every wallpaper given, then prints one
# "wallpaper<TAB>thumbnail" line per wallpaper that has one. Without these the
# deck decoded the full images itself: a 12 MB PNG did not finish before the
# deck was released, and Qt cannot read WebP at all without an extra plugin,
# so those cards stayed blank.
#
# Thumbnails are keyed by path, size and mtime, so an edited or replaced file
# gets a new one. Thumbnails of files no longer listed are deleted.
# A file magick cannot read is skipped; the deck then shows the original.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

THUMB_DIR="$CACHE_DIR/wallpaper-thumbs"
# Same size and aspect as a deck card (cardW x cardH, with headroom for
# fractional scaling).
THUMB_GEOMETRY="520x728"

mkdir -p "$THUMB_DIR"

declare -A thumb_of
missing=()
for wallpaper in "$@"; do
    [[ -f $wallpaper ]] || continue
    key=$(stat -c '%s %Y' -- "$wallpaper" 2>/dev/null) || continue
    hash=$(printf '%s %s' "$wallpaper" "$key" | sha1sum)
    thumb="$THUMB_DIR/${hash%% *}.jpg"
    thumb_of[$wallpaper]=$thumb
    [[ -s $thumb ]] || missing+=("$wallpaper" "$thumb")
done

# One thumbnail. "[0]" takes the first frame of a GIF. Written to a temp name
# first so a half-written file is never listed.
make_thumb() {
    local src=$1 dest=$2
    magick "${src}[0]" -auto-orient -thumbnail "${THUMB_GEOMETRY}^" \
        -gravity center -extent "$THUMB_GEOMETRY" -quality 85 \
        "jpg:${dest}.tmp" 2>/dev/null && mv -f "${dest}.tmp" "$dest"
    rm -f "${dest}.tmp"
}
export -f make_thumb
export THUMB_GEOMETRY

# Build the missing ones in parallel; each job gets a source and a target line.
if ((${#missing[@]})); then
    printf '%s\n' "${missing[@]}" |
        xargs -d '\n' -P "$(nproc)" -n 2 bash -c 'make_thumb "$1" "$2"' _
fi

# Drop thumbnails that no listed wallpaper points at any more.
declare -A keep
for thumb in "${thumb_of[@]}"; do keep[$thumb]=1; done
for thumb in "$THUMB_DIR"/*.jpg; do
    [[ -e $thumb && -z ${keep[$thumb]:-} ]] && rm -f "$thumb"
done

for wallpaper in "${!thumb_of[@]}"; do
    [[ -s ${thumb_of[$wallpaper]} ]] && printf '%s\t%s\n' "$wallpaper" "${thumb_of[$wallpaper]}"
done
exit 0
