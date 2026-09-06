#!/bin/bash
# default-app.sh — which application fills a role, and how to launch it.
#
#   default-app.sh get  <role>                 -> desktop id, or empty
#   default-app.sh set  <role> <desktop-id>    -> persist (and register with XDG)
#   default-app.sh run  <role> [args...]       -> launch the current choice
#
# Roles: browser terminal editor filemanager
#
# Browser and file manager have real XDG defaults, so `set` writes those too —
# picking a browser here should also change what a link in a chat app opens.
# Terminal and editor have no such standard, which is why this file exists at
# all: the Hyprland binds call `run` instead of hardcoding a command.
set -uo pipefail

source "$HOME/.config/scripts/lib/notify.sh"

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/default-apps.conf"

# Last-resort commands, used when nothing is configured yet.
fallback_for() {
    case "$1" in
        browser)     echo "xdg-open about:blank" ;;
        terminal)    echo "kitty" ;;
        editor)      echo "kitty -e nvim" ;;
        filemanager) echo "nautilus" ;;
        *)           echo "" ;;
    esac
}

conf_get() {
    [[ -f "$CONF" ]] || return 0
    local line
    line=$(grep -E "^$1=" "$CONF" | tail -1) || return 0
    echo "${line#*=}"
}

conf_set() {
    local role=$1 id=$2 tmp
    mkdir -p "$(dirname "$CONF")"
    touch "$CONF"
    tmp=$(mktemp)
    grep -vE "^$role=" "$CONF" > "$tmp" 2>/dev/null
    echo "$role=$id" >> "$tmp"
    mv "$tmp" "$CONF"
}

# XDG's own answer, so a role that has one is not tracked in two places when
# something else (a browser's "make me default" prompt) changes it behind us.
xdg_get() {
    case "$1" in
        browser)     xdg-settings get default-web-browser 2>/dev/null ;;
        filemanager) xdg-mime query default inode/directory 2>/dev/null ;;
    esac
}

get_role() {
    local role=$1 id
    id=$(xdg_get "$role")
    [[ -n "$id" ]] && { echo "$id"; return 0; }
    conf_get "$role"
}

set_role() {
    local role=$1 id=$2
    [[ "$id" == *.desktop ]] || id="$id.desktop"
    conf_set "$role" "$id"

    case "$role" in
        browser)
            xdg-settings set default-web-browser "$id" 2>/dev/null
            xdg-mime default "$id" x-scheme-handler/http x-scheme-handler/https text/html
            ;;
        filemanager)
            xdg-mime default "$id" inode/directory
            ;;
    esac

    local label="${id%.desktop}"
    notify low default-app applications-system "Default $role" "Now $label"
}

# `gio launch` wants a path, not an id — handed a bare id it looks in $PWD and
# fails. Search the XDG application directories for the entry.
resolve_desktop() {
    local id=$1 dir
    [[ "$id" == /* ]] && { [[ -f "$id" ]] && echo "$id"; return; }
    local -a dirs=("$HOME/.local/share/applications")
    IFS=: read -ra xdg <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for dir in "${xdg[@]}"; do dirs+=("$dir/applications"); done
    for dir in "${dirs[@]}"; do
        [[ -f "$dir/$id" ]] && { echo "$dir/$id"; return; }
    done
}

run_role() {
    local role=$1; shift
    local id path fb
    id=$(get_role "$role")
    [[ -n "$id" ]] && path=$(resolve_desktop "$id")
    if [[ -n "${path:-}" ]]; then
        exec gio launch "$path" "$@"
    fi
    # Nothing chosen, or the entry has gone missing: run the built-in.
    fb=$(fallback_for "$role")
    [[ -z "$fb" ]] && exit 1
    # shellcheck disable=SC2086  # split on purpose: the fallback is a command line
    exec setsid -f $fb "$@"
}

role=${2:-}
case "${1:-}" in
    get) [[ -z "$role" ]] && { echo "usage: $0 get <role>" >&2; exit 2; }
         get_role "$role" ;;
    set) [[ -z "$role" || -z "${3:-}" ]] && { echo "usage: $0 set <role> <desktop-id>" >&2; exit 2; }
         set_role "$role" "$3" ;;
    run) [[ -z "$role" ]] && { echo "usage: $0 run <role> [args...]" >&2; exit 2; }
         shift 2
         run_role "$role" "$@" ;;
    *)   echo "usage: $0 {get|set|run} <role> [args...]" >&2; exit 2 ;;
esac
