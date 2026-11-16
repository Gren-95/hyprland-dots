#!/bin/bash
# Print the file of an app icon from the icon theme, or nothing.
#
# Usage: icon-path.sh <icon-name>
#
# For the Sound popup's app rows (quickshell/AudioAppRow.qml): Quickshell's
# image://icon provider drew nothing when the icon name reached the image
# through a binding, so the row resolves a real file and loads it with file://.
# Looks in the user's icons, then Papirus-Dark, Papirus and hicolor at sizes
# that render sharply at 30 px, then /usr/share/pixmaps.
set -uo pipefail

name=${1:-}
[[ -n $name && $name != */* ]] || exit 0

for base in "$HOME/.local/share/icons" /usr/share/icons; do
    for theme in Papirus-Dark Papirus hicolor; do
        for size in 48x48 64x64 scalable 128x128 32x32 256x256; do
            for ext in svg png; do
                f="$base/$theme/$size/apps/$name.$ext"
                if [[ -e $f ]]; then
                    readlink -f -- "$f"
                    exit 0
                fi
            done
        done
    done
done
for ext in svg png; do
    [[ -e /usr/share/pixmaps/$name.$ext ]] && readlink -f -- "/usr/share/pixmaps/$name.$ext" && exit 0
done
exit 0
