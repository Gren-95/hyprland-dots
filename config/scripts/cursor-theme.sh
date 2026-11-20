#!/bin/bash
# List, read and switch the cursor theme.
#
# Usage:
#   cursor-theme.sh list        JSON array of cursor themes with preview images
#   cursor-theme.sh get         {"apps": <XCURSOR_THEME>, "hyprland": <HYPRCURSOR_THEME>}
#   cursor-theme.sh set <id>    switch to the theme with that directory name
#   cursor-theme.sh size <px>   switch the cursor size (Appearance in the app)
#
# The settings app's Appearance panel (icon and cursor themes) (apps/settings, themes.rs) calls
# all three; `list` is cursor-previews.py.
#
# The themes live in the hl.env lines of config/hypr/modules/autostart.lua.
# An XCursor theme is for apps and for Hyprland: `set` writes it to both
# XCURSOR_THEME and HYPRCURSOR_THEME (Hyprland draws the XCursor theme of the
# same name when there is no Hyprcursor one) and to gsettings. A Hyprcursor
# theme is only for Hyprland, so it replaces HYPRCURSOR_THEME and leaves the
# apps' theme alone. `hyprctl setcursor` switches the Hyprland cursor at once;
# apps that are already running keep their old cursor until they restart.
set -uo pipefail

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
AUTOSTART="$HOME/.config/hypr/modules/autostart.lua"
THEME_DIRS=("$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons)

env_value() {
    sed -n "s/^hl\.env(\"$1\", \"\(.*\)\")$/\1/p" "$AUTOSTART"
}

set_env() {
    sed -i --follow-symlinks "s/^hl\.env(\"$1\", \".*\")$/hl.env(\"$1\", \"$2\")/" "$AUTOSTART"
}

theme_dir() {
    local base
    for base in "${THEME_DIRS[@]}"; do
        if [[ -f $base/$1/manifest.hl || -d $base/$1/cursors ]]; then
            printf '%s\n' "$base/$1"
            return 0
        fi
    done
    return 1
}

apply() {
    local id=$1 dir size
    [[ $id =~ ^[A-Za-z0-9._+-]+$ ]] || {
        echo "cursor-theme: invalid theme name: $id" >&2
        exit 1
    }
    dir=$(theme_dir "$id") || {
        echo "cursor-theme: not installed: $id" >&2
        exit 1
    }
    if [[ -f $dir/manifest.hl ]]; then
        set_env HYPRCURSOR_THEME "$id"
    else
        set_env XCURSOR_THEME "$id"
        set_env HYPRCURSOR_THEME "$id"
        gsettings set org.gnome.desktop.interface cursor-theme "$id"
    fi
    size=$(env_value HYPRCURSOR_SIZE)
    hyprctl setcursor "$id" "${size:-24}" >/dev/null
}

# Cursor size for Hyprland, apps (XCURSOR_SIZE, gsettings) and now.
resize() {
    local px=$1
    [[ $px =~ ^[0-9]{2,3}$ ]] || {
        echo "cursor-theme: invalid size: $px" >&2
        exit 1
    }
    set_env XCURSOR_SIZE "$px"
    set_env HYPRCURSOR_SIZE "$px"
    gsettings set org.gnome.desktop.interface cursor-size "$px"
    hyprctl setcursor "$(env_value HYPRCURSOR_THEME)" "$px" >/dev/null
}

case ${1:-} in
    list) exec python3 "$SCRIPT_DIR/cursor-previews.py" ;;
    get) jq -n --arg apps "$(env_value XCURSOR_THEME)" --arg hyprland "$(env_value HYPRCURSOR_THEME)" \
        '{apps: $apps, hyprland: $hyprland}' ;;
    set) apply "${2:-}" ;;
    size) resize "${2:-}" ;;
    *)
        echo "usage: cursor-theme.sh list | get | set <id> | size <px>" >&2
        exit 2
        ;;
esac
