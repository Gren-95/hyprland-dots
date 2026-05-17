#!/bin/bash
# dotwatch.sh — Watch dotfiles for changes and hot-reload affected services
#
# Add to hyprland.conf:  exec-once = bash ~/.config/scripts/dotwatch.sh
# Also called from restart.sh
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"

DOTS_DIR="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
COOLDOWN=2
declare -A LAST_RELOAD

log() { echo "[$(date '+%H:%M:%S')] dotwatch: $*"; }

can_reload() {
    local key="$1" now
    now=$(date +%s)
    (( now - ${LAST_RELOAD[$key]:-0} >= COOLDOWN )) || return 1
    LAST_RELOAD[$key]=$now
}

reload_hyprland() {
    can_reload hyprland || return
    log "hyprland → reloading config"
    hyprctl reload
}

reload_hypridle() {
    can_reload hypridle || return
    log "hypridle → restarting"
    pkill -x hypridle 2>/dev/null
    hypridle >/dev/null 2>&1 &
}

notify_hyprlock() {
    can_reload hyprlock || return
    log "hyprlock.conf → saved"
    notify low dotwatch-hyprlock system-lock-screen "Hyprlock updated" "Changes apply on next lock"
}

notify_gtk() {
    can_reload gtk || return
    log "gtk-3.0/gtk.css → updated (restart GTK apps to apply)"
    notify low dotwatch-gtk preferences-desktop-theme "GTK CSS updated" "Restart GTK apps to apply changes"
}

log "Watching $DOTS_DIR"

inotifywait -m -r -e close_write,moved_to,create \
    --exclude '\.git' \
    --format '%w%f' \
    "$DOTS_DIR" 2>/dev/null | while read -r path; do

    rel="${path#$DOTS_DIR/}"

    case "$rel" in
        hypr/hyprland.conf|hypr/modules/*) reload_hyprland ;;
        hypr/hypridle.conf)                reload_hypridle ;;
        hypr/hyprlock.conf)                notify_hyprlock ;;
        gtk-3.0/gtk.css)                   notify_gtk ;;
    esac
done
