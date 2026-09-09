#!/bin/bash
# Copies the current MPRIS album art to a fixed path for hyprlock to read, and
# repoints the lock background at a random wallpaper.
#
# Two rules this script has to obey, both learned from it breaking:
#
#   1. It always exits 0. hypridle chains the lock behind it, and a missing
#      album cover must never be the reason a suspend goes unlocked.
#   2. It leaves $LOCK_ART either correct or absent, never stale. Bailing out
#      halfway used to leave the previous track's cover sitting on the lock
#      screen.
#
# With --print it re-fetches the art and writes its path to stdout, which is
# what hyprlock's image reload_cmd consumes; printing nothing leaves hyprlock
# showing whatever it already has. In that mode the wallpaper is left alone,
# since reload_cmd fires every couple of seconds.
#
# stderr is kept clean: hyprlock logs anything a reload_cmd writes there as an
# error.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

DEST="$LOCK_ART"
PRINT=0
[[ ${1:-} == --print ]] && PRINT=1

publish() {
    ((PRINT)) && printf '%s\n' "$DEST"
    exit 0
}

# No art, or we could not get it: drop the file so nothing stale is shown.
give_up() {
    rm -f "$DEST"
    exit 0
}

if ((!PRINT)); then
    WP=$(find "$WALLPAPER_DIR" -type f \
        \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' \) \
        2>/dev/null | shuf -n1)
    [[ -n $WP && -f $WP ]] && ln -sf "$WP" "$LOCK_BG"
fi

# playerctl exits non-zero when no player is registered, which is the normal
# case rather than an error.
url=$(playerctl metadata mpris:artUrl 2>/dev/null) || url=""
[[ -n $url ]] || give_up

tmp=$(mktemp "${DEST}.XXXXXX" 2>/dev/null) || give_up
trap 'rm -f "$tmp"' EXIT

if [[ $url == file://* ]]; then
    # MPRIS percent-encodes the path, so %20 and friends have to be decoded
    # before cp can find the file.
    src=${url#file://}
    src=$(printf '%b' "${src//%/\\x}")
    cp -- "$src" "$tmp" 2>/dev/null || give_up
else
    curl -sf --max-time 5 -o "$tmp" -- "$url" 2>/dev/null || give_up
fi

# A truncated download leaves a zero-byte file, which renders as a broken box.
[[ -s $tmp ]] || give_up

mv -f "$tmp" "$DEST" 2>/dev/null || give_up
trap - EXIT
publish
