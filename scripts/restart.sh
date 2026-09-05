#!/bin/bash
# Hyprland services restart script
# Restarts all services started via exec-once in hyprland.conf
# Uses -uo pipefail (no -e): we want every restart step to run even if some fail.
#
# Runs on hyprland.start (autostart.lua) as well as from Super+B, so its
# runtime is felt directly at login. Everything here is therefore structured
# to avoid fixed sleeps: processes are killed in one batch, started in one
# batch, and only then polled for readiness. A daemon that comes up in 20 ms
# costs 20 ms instead of a flat 200 ms.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

SCRIPTS="$HOME/.config/scripts"

# Poll until a process matching the pattern exists. $2 = pgrep mode (-f or -x),
# $3 = timeout in centiseconds (default 200 = 2 s).
wait_for() {
    local pattern="$1" mode="${2:--f}" limit="${3:-200}" i=0
    while (( i < limit )); do
        pgrep "$mode" "$pattern" >/dev/null 2>&1 && return 0
        sleep 0.01
        (( i++ ))
    done
    return 1
}

# Poll until a D-Bus name is actually owned. A portal's process existing is not
# the same as it having acquired its name on the bus, and Quickshell needs the
# latter — waiting on the process alone still lost the registration.
wait_for_dbus() {
    local name="$1" limit="${2:-300}" i=0
    while (( i < limit )); do
        busctl --user list --acquired --no-legend 2>/dev/null \
            | awk '{print $1}' | grep -qx "$name" && return 0
        sleep 0.01
        (( i++ ))
    done
    return 1
}

report() { # name pattern mode
    printf 'Running: %-22s ... ' "$1"
    if wait_for "$2" "${3:--f}"; then echo "OK"; else echo "FAILED"; fi
}

echo "======================================"
echo "Restarting Hyprland Services"
echo "======================================"

################################################################################
# 1. Kill everything up front, in one pass, with no waiting in between.
################################################################################
pkill -f xdg-desktop-portal            2>/dev/null
pkill -x gnome-keyring-daemon          2>/dev/null
pkill -f "qs -p"                       2>/dev/null
killall hyprpaper                      2>/dev/null
killall hypridle                       2>/dev/null
pkill -f power-auto.sh                 2>/dev/null
pkill -f battery-notify.sh             2>/dev/null
pkill -f dotwatch.sh                   2>/dev/null
pkill -f "wl-paste.*cliphist"          2>/dev/null
# These two trap SIGTERM to release their D-Bus inhibitor. Signal them now and
# SIGKILL further down: the work in between is the grace period, so we no
# longer pay a dedicated sleep for it.
pkill -TERM -f media-inhibit.sh        2>/dev/null
pkill -TERM -f fullscreen-inhibit.sh   2>/dev/null
# Polkit is provided by Quickshell (quickshell/PolkitPrompt.qml); clear any
# agent left over from a previous session.
systemctl --user stop hyprpolkitagent  2>/dev/null
pkill -x hyprpolkitagent               2>/dev/null
pkill -x lxpolkit                      2>/dev/null
pkill -x xfce-polkit                   2>/dev/null

################################################################################
# 2. gnome-keyring first: its eval exports SSH_AUTH_SOCK into this shell, so it
#    has to run before anything that should inherit it.
################################################################################
printf 'Running: %-22s ... ' "gnome-keyring-daemon"
# stderr must be silenced INSIDE the substitution: $() captures stdout only,
# so the daemon's chatter would otherwise land mid-line on the status output.
eval "$(/usr/bin/gnome-keyring-daemon --start --components=pkcs11,secrets,ssh,gpg 2>/dev/null)" >/dev/null 2>&1
if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
    export SSH_AUTH_SOCK
    echo "OK"
else
    echo "FAILED"
fi

################################################################################
# 3. Portals BEFORE Quickshell. Quickshell registers with
#    org.freedesktop.portal.Desktop as it starts; if the portal is not up yet
#    it logs "Could not activate remote peer" and loses file-picker/screencast
#    integration for the session. The generic portal in turn needs its
#    Hyprland backend first, so this is a chain — but each link waits on the
#    previous one appearing, not on a fixed delay.
################################################################################
/usr/libexec/xdg-desktop-portal-hyprland >/dev/null 2>&1 &
wait_for_dbus org.freedesktop.impl.portal.desktop.hyprland 300
/usr/libexec/xdg-desktop-portal >/dev/null 2>&1 &
wait_for_dbus org.freedesktop.portal.Desktop 300

################################################################################
# 4. Quickshell — the visible one (bar, notifications, OSDs).
################################################################################
QT_QPA_PLATFORMTHEME=hyprqt6engine qs -p "$HOME/.config/quickshell/shell.qml" -d >/dev/null 2>&1

################################################################################
# 5. Regenerate the hyprpaper config. One find pass, not two.
################################################################################
mkdir -p "$CACHE_DIR"
mapfile -t WALLPAPERS < <(find "$WALLPAPER_DIR" -type f \
    \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.webp" \) 2>/dev/null | sort)
{
    echo "splash = false"
    for f in "${WALLPAPERS[@]}"; do echo "preload = $f"; done
    [[ ${#WALLPAPERS[@]} -gt 0 ]] && echo "wallpaper = ,${WALLPAPERS[0]}"
} > "$HYPRPAPER_CACHE"

################################################################################
# 6. Start the rest. All independent of each other, so start them back to back
#    and verify afterwards rather than one-at-a-time.
################################################################################
pkill -KILL -f media-inhibit.sh      2>/dev/null
pkill -KILL -f fullscreen-inhibit.sh 2>/dev/null

hyprpaper -c "$HYPRPAPER_CACHE"           >/dev/null 2>&1 &
hypridle                                  >/dev/null 2>&1 &
bash "$SCRIPTS/battery-notify.sh"         >/dev/null 2>&1 &
bash "$SCRIPTS/media-inhibit.sh"          >/dev/null 2>&1 &
bash "$SCRIPTS/fullscreen-inhibit.sh"     >/dev/null 2>&1 &
bash "$SCRIPTS/dotwatch.sh"               >/dev/null 2>&1 &
wl-paste --watch cliphist store           >/dev/null 2>&1 &
# power-auto.sh is ALSO started by autostart.lua on hyprland.start. Starting it
# here too raced the two copies at login; the pkill above clears any existing
# one and this is the single owner.
bash "$SCRIPTS/power-auto.sh"             >/dev/null 2>&1 &

################################################################################
# 7. One-shot settings. Measured at ~0.04 s combined, so they stay inline.
################################################################################
nmcli radio wifi on >/dev/null 2>&1
dbus-update-activation-environment --systemd --all >/dev/null 2>&1
gsettings set org.gnome.desktop.interface gtk-theme "Adwaita" >/dev/null 2>&1
gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark" >/dev/null 2>&1
gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" >/dev/null 2>&1
hyprctl keyword monitor "FALLBACK,1920x1080@60,auto,1" >/dev/null 2>&1
bash "$SCRIPTS/wallpaper.sh" >/dev/null 2>&1

################################################################################
# 8. Verify. By now most daemons are already up, so these return immediately.
################################################################################
report "quickshell"          "qs -p"
report "xdg-desktop-portal"  "xdg-desktop-portal"
report "hyprpaper"           "hyprpaper"            -x
report "hypridle"            "hypridle"             -x
report "power-auto"          "power-auto.sh"
report "battery-notify"      "battery-notify.sh"
report "media-inhibit"       "media-inhibit.sh"
report "fullscreen-inhibit"  "fullscreen-inhibit.sh"
report "cliphist"            "wl-paste.*cliphist"
report "dotwatch"            "dotwatch.sh"

# WayVNC is not auto-started; stop a stale one (restart with Super+Shift+V).
printf 'Running: %-22s ... ' "wayvnc"
if pgrep -x wayvnc >/dev/null; then
    pkill wayvnc
    echo "SKIPPED (stopped — restart with Super+Shift+V)"
else
    echo "SKIPPED (not running)"
fi

echo "======================================"
echo "Restart Complete!"
echo "======================================"
