#!/bin/bash
# settings.sh — read the shell's settings store from scripts.
#
# Source (after paths.sh):
#   setting <file> <default>         first line of the setting, or the default
#   valid <value> <regex> <default>  the value when it matches, else the default
#   setting_dir <file> <default>     a folder setting: ~ expanded, absolute only
#
# The store is one small file per setting in ~/.config/quickshell/settings/
# (quickshell/Settings.qml); the settings app and the shell write it.

SETTINGS_DIR="$CONFIG_DIR/quickshell/settings"

setting() {
    local file="$SETTINGS_DIR/$1" value=""
    [[ -f $file ]] && IFS= read -r value <"$file"
    printf '%s' "${value:-$2}"
}

valid() {
    if [[ $1 =~ ^($2)$ ]]; then printf '%s' "$1"; else printf '%s' "$3"; fi
}

setting_dir() {
    local dir
    dir=$(setting "$1" "$2")
    dir=${dir/#\~/$HOME}
    [[ $dir == /* ]] || dir=$2
    printf '%s' "$dir"
}
