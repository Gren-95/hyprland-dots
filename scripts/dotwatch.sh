#!/bin/bash
# dotwatch.sh — Watch dotfiles for changes and hot-reload affected services
#
# Add to hyprland.conf:  exec-once = bash ~/.config/scripts/dotwatch.sh
# Also called from restart.sh

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

reload_waybar() {
    can_reload waybar || return
    log "waybar → restarting"
    killall waybar 2>/dev/null
    local conf="$WAYBAR_DIR/config-active"
    local css="$WAYBAR_DIR/style-active.css"
    [[ ! -L "$conf" ]] && conf="$WAYBAR_DIR/config"
    [[ ! -L "$css" ]] && css="$WAYBAR_DIR/style.css"
    waybar -c "$conf" -s "$css" >/dev/null 2>&1 &
}

reload_swaync_css() {
    can_reload swaync || return
    log "swaync → reloading CSS"
    swaync-client --reload-css
}

reload_swaync_config() {
    can_reload swaync || return
    log "swaync → reloading config"
    swaync-client --reload-config
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
        waybar/style*.css|waybar/config*)  reload_waybar ;;
        swaync/style.css)                  reload_swaync_css ;;
        swaync/config.json)                reload_swaync_config ;;
        hypr/hyprland.conf|hypr/modules/*) reload_hyprland ;;
        hypr/hypridle.conf)                reload_hypridle ;;
        hypr/hyprlock.conf)                notify_hyprlock ;;
        gtk-3.0/gtk.css)                   notify_gtk ;;
    esac
done
