#!/bin/bash
# Hyprland services restart script
# Restarts all services started via exec-once in hyprland.conf
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

echo "======================================"
echo "Restarting Hyprland Services"
echo "======================================"

# Restart XDG desktop portal (required for screen sharing, file pickers, etc.)
echo -n "Running: xdg-desktop-portal-hyprland ... "
pkill -f xdg-desktop-portal 2>/dev/null
sleep 0.5
/usr/libexec/xdg-desktop-portal-hyprland >/dev/null 2>&1 &
sleep 0.3
/usr/libexec/xdg-desktop-portal >/dev/null 2>&1 &
sleep 0.3
if pgrep -f xdg-desktop-portal >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Restart gnome-keyring-daemon
echo -n "Running: gnome-keyring-daemon ... "
pkill -x gnome-keyring-daemon 2>/dev/null
eval $(/usr/bin/gnome-keyring-daemon --start --components=pkcs11,secrets,ssh,gpg) >/dev/null 2>&1
if [[ $? -eq 0 ]] && [[ -n "$SSH_AUTH_SOCK" ]]; then
    export SSH_AUTH_SOCK
    echo "OK"
else
    echo "FAILED"
fi

# Restart Quickshell (bar + notifications + OSDs)
echo -n "Running: quickshell ... "
killall waybar 2>/dev/null
pkill -f "qs -p" 2>/dev/null
sleep 0.2
QT_QPA_PLATFORMTHEME=hyprqt6engine qs -p "$HOME/.config/quickshell/shell.qml" -d >/dev/null 2>&1
sleep 0.3
if pgrep -f "qs -p" >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Generate hyprpaper config from all wallpapers in ~/Pictures/wallpapers/
mkdir -p "$CACHE_DIR"
{
    echo "splash = false"
    find "$WALLPAPER_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.webp" \) \
        2>/dev/null | sort | while read -r f; do echo "preload = $f"; done
    FIRST_WP=$(find "$WALLPAPER_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.webp" \) 2>/dev/null | sort | head -1)
    [[ -n "$FIRST_WP" ]] && echo "wallpaper = ,$FIRST_WP"
} > "$HYPRPAPER_CACHE"

# Restart Hyprpaper
echo -n "Running: hyprpaper ... "
killall hyprpaper 2>/dev/null
hyprpaper -c "$HYPRPAPER_CACHE" >/dev/null 2>&1 &
sleep 0.2
if pgrep -x hyprpaper >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Restart Hypridle
echo -n "Running: hypridle ... "
killall hypridle 2>/dev/null
hypridle >/dev/null 2>&1 &
sleep 0.2
if pgrep -x hypridle >/dev/null; then echo "OK"; else echo "FAILED"; fi

# swaync and swayosd replaced by quickshell's NotificationServer and Osd.qml;
# stop any stale instances.
killall swaync 2>/dev/null
killall swayosd-server 2>/dev/null
pkill -f swayosd-monitor.sh 2>/dev/null

# Restart battery notifier
echo -n "Running: battery-notify ... "
pkill -f battery-notify.sh 2>/dev/null
bash "$HOME/.config/scripts/battery-notify.sh" >/dev/null 2>&1 &
sleep 0.2
if pgrep -f battery-notify.sh >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Restart media inhibit (prevents screen sleep during playback)
echo -n "Running: media-inhibit ... "
pkill -f media-inhibit.sh 2>/dev/null
bash "$HOME/.config/scripts/media-inhibit.sh" >/dev/null 2>&1 &
sleep 0.2
if pgrep -f media-inhibit.sh >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Restart cliphist daemon (Wayland clipboard history)
echo -n "Running: cliphist ... "
pkill -f "wl-paste.*cliphist" 2>/dev/null
wl-paste --watch cliphist store >/dev/null 2>&1 &
sleep 0.2
if pgrep -f "wl-paste.*cliphist" >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Restart nm-applet (system tray network indicator)
echo -n "Running: nm-applet ... "
pkill -x nm-applet 2>/dev/null
nm-applet --indicator >/dev/null 2>&1 &
sleep 0.2
if pgrep -x nm-applet >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Restart network notifier
echo -n "Running: network-notify ... "
pkill -f network-notify.sh 2>/dev/null
bash "$HOME/.config/scripts/network-notify.sh" >/dev/null 2>&1 &
sleep 0.2
if pgrep -f network-notify.sh >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Restart immich sync daemon
echo -n "Running: immich-sync ... "
pkill -f immich-sync.sh 2>/dev/null
bash -c 'command -v immich >/dev/null 2>&1 || [[ -x ~/.npm-global/bin/immich ]] && exec bash ~/.config/scripts/immich-sync.sh' >/dev/null 2>&1 &
sleep 0.2
if pgrep -f immich-sync.sh >/dev/null; then echo "OK"; else echo "SKIPPED (immich not installed)"; fi

# Restart jellyfin sync daemon
echo -n "Running: jellyfin-sync ... "
pkill -f jellyfin-music-sync.sh 2>/dev/null
bash -c '[[ -f ~/.config/jellyfin/sync.conf ]] && exec bash ~/.config/scripts/jellyfin-music-sync.sh --daemon' >/dev/null 2>&1 &
sleep 0.2
if pgrep -f jellyfin-music-sync.sh >/dev/null; then echo "OK"; else echo "SKIPPED (no config)"; fi

# Enable WiFi
echo -n "Running: nmcli radio wifi on ... "
nmcli radio wifi on >/dev/null 2>&1
if [[ $? -eq 0 ]]; then echo "OK"; else echo "FAILED"; fi

# Polkit agent is provided by Quickshell (quickshell/PolkitPrompt.qml).
# Stop hyprpolkitagent if it's still running from a previous session.
systemctl --user stop hyprpolkitagent 2>/dev/null
pkill -x hyprpolkitagent 2>/dev/null
pkill -x lxpolkit 2>/dev/null
pkill -x xfce-polkit 2>/dev/null

# Run wallpaper script
echo -n "Running: wallpaper.sh ... "
bash "$HOME/.config/scripts/wallpaper.sh" >/dev/null 2>&1
if [[ $? -eq 0 ]]; then echo "OK"; else echo "FAILED"; fi

# Update environment
echo -n "Running: dbus-update-activation-environment ... "
dbus-update-activation-environment --systemd --all >/dev/null 2>&1
if [[ $? -eq 0 ]]; then echo "OK"; else echo "FAILED"; fi

# Set GTK theme and dark mode preference
echo -n "Running: gsettings (GTK theme) ... "
gsettings set org.gnome.desktop.interface gtk-theme "Adwaita" >/dev/null 2>&1 && \
gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" >/dev/null 2>&1
if [[ $? -eq 0 ]]; then echo "OK"; else echo "FAILED"; fi

# Set fallback monitor
echo -n "Running: hyprctl monitor fallback ... "
hyprctl keyword monitor "FALLBACK,1920x1080@60,auto,1" >/dev/null 2>&1
if [[ $? -eq 0 ]]; then echo "OK"; else echo "FAILED"; fi

# Restart dotwatch (inotify hot-reload daemon)
echo -n "Running: dotwatch ... "
pkill -f dotwatch.sh 2>/dev/null
bash "$HOME/.config/scripts/dotwatch.sh" >/dev/null 2>&1 &
sleep 0.2
if pgrep -f dotwatch.sh >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Stop WayVNC if running (user can restart manually with Super+Shift+V)
echo -n "Running: wayvnc ... "
if pgrep -x wayvnc >/dev/null; then
    pkill wayvnc
    echo "SKIPPED (stopped — restart with Super+Shift+V)"
else
    echo "SKIPPED (not running)"
fi

echo "======================================"
echo "Restart Complete!"
echo "======================================"
