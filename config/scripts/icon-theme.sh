#!/bin/bash
# List, read and switch the icon theme.
#
# Usage:
#   icon-theme.sh list        JSON array of installed icon themes with sample icons
#   icon-theme.sh get         name of the current icon theme
#   icon-theme.sh set <id>    switch to the theme with that directory name
#
# The Icon theme popup (quickshell/IconThemes.qml) calls all three.
# `list` prints [{id, name, comment, samples: [file, ...]}], one sample per
# slot in SAMPLE_SLOTS, taken from the theme itself (not from the themes it
# inherits) so every pack shows its own art. Themes with fewer than
# MIN_SAMPLES of them (cursor themes, hicolor) are left out.
#
# The current theme lives in config/gtk-3.0/settings.ini. `set` writes it
# there, in config/gtk-4.0/settings.ini, in config/hypr/hyprqt6engine.conf
# (Qt apps) and in gsettings (GTK 4 through the settings portal). Running
# apps keep the old icons until they restart.
set -uo pipefail

GTK3_INI="$HOME/.config/gtk-3.0/settings.ini"
GTK4_INI="$HOME/.config/gtk-4.0/settings.ini"
QT_CONF="$HOME/.config/hypr/hyprqt6engine.conf"
THEME_DIRS=("$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons)
# One slot per sample; the first name a theme has wins.
SAMPLE_SLOTS=(
    "firefox web-browser"
    "org.gnome.Nautilus system-file-manager"
    "utilities-terminal kitty"
    "preferences-system org.gnome.Settings"
    "folder"
    "folder-download"
    "text-x-generic"
    "image-x-generic"
)
MIN_SAMPLES=4

current() {
    sed -n 's/^gtk-icon-theme-name=//p' "$GTK3_INI"
}

# Print "<id>\t<dir>" for every icon theme, the first directory winning when
# the same id is installed twice.
theme_dirs() {
    local base dir id
    declare -A seen=()
    for base in "${THEME_DIRS[@]}"; do
        for dir in "$base"/*/; do
            dir=${dir%/}
            id=${dir##*/}
            [[ -f $dir/index.theme && -z ${seen[$id]:-} ]] || continue
            seen[$id]=1
            printf '%s\t%s\n' "$id" "$dir"
        done
    done
}

# index.theme key from the [Icon Theme] section.
theme_key() {
    awk -F= -v key="$2" '
        /^\[/ { inside = ($0 == "[Icon Theme]") }
        inside && $1 == key { sub(/^[^=]*=/, ""); print; exit }
    ' "$1/index.theme"
}

# Best file for each slot: the smallest size of at least 48 px, scalable
# counting as the largest. Prints one path per found slot, in slot order.
samples() {
    local dir=$1 slot name
    local -a find_args=()
    for slot in "${SAMPLE_SLOTS[@]}"; do
        for name in $slot; do
            find_args+=(-o -name "$name.svg" -o -name "$name.png")
        done
    done
    find -L "$dir" -type f \( "${find_args[@]:1}" \) 2>/dev/null |
        awk -v slots="$(printf '%s|' "${SAMPLE_SLOTS[@]}")" '
            BEGIN {
                n = split(slots, s, "|")
                for (i = 1; i < n; i++) {
                    k = split(s[i], names, " ")
                    for (j = 1; j <= k; j++) { slot[names[j]] = i; rank[names[j]] = j }
                }
                count = n - 1
            }
            {
                file = $0
                sub(/.*\//, "", file)
                sub(/\.(svg|png)$/, "", file)
                if (!(file in slot) || $0 ~ /symbolic/) next
                size = 1000
                if (match($0, /\/[0-9]+(x[0-9]+)?(@[0-9]x)?\//)) {
                    size = substr($0, RSTART + 1, RLENGTH - 2) + 0
                }
                if (size < 48) size += 2000          # too small: only when nothing else
                score = rank[file] * 10000 + size
                i = slot[file]
                if (!(i in best) || score < best[i]) { best[i] = score; path[i] = $0 }
            }
            END { for (i = 1; i <= count; i++) if (i in path) print path[i] }
        '
}

list() {
    local id dir name comment
    local -a files
    while IFS=$'\t' read -r id dir; do
        [[ $(theme_key "$dir" Hidden) == true ]] && continue
        mapfile -t files < <(samples "$dir")
        ((${#files[@]} >= MIN_SAMPLES)) || continue
        name=$(theme_key "$dir" Name)
        comment=$(theme_key "$dir" Comment)
        jq -n --arg id "$id" --arg name "${name:-$id}" --arg comment "$comment" \
            '{id: $id, name: $name, comment: $comment, samples: $ARGS.positional}' \
            --args "${files[@]}"
    done < <(theme_dirs) | jq -s 'sort_by(.name | ascii_downcase)'
}

apply() {
    local id=$1
    [[ $id =~ ^[A-Za-z0-9._+-]+$ ]] || {
        echo "icon-theme: invalid theme name: $id" >&2
        exit 1
    }
    if ! theme_dirs | cut -f1 | grep -qxF -- "$id"; then
        echo "icon-theme: not installed: $id" >&2
        exit 1
    fi
    sed -i --follow-symlinks "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$id/" "$GTK3_INI" "$GTK4_INI"
    sed -i --follow-symlinks "s/^\([[:space:]]*icon_theme[[:space:]]*=\).*/\1 $id/" "$QT_CONF"
    gsettings set org.gnome.desktop.interface icon-theme "$id"
}

case ${1:-} in
    list) list ;;
    get) current ;;
    set) apply "${2:-}" ;;
    *)
        echo "usage: icon-theme.sh list | get | set <id>" >&2
        exit 2
        ;;
esac
