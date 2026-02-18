#!/bin/bash
# Hyprland services restart script
# Restarts all services started via exec-once in hyprland.conf

echo "======================================"
echo "Restarting Hyprland Services"
echo "======================================"

# Start gnome-keyring-daemon
echo -n "Running: gnome-keyring-daemon ... "
eval $(/usr/bin/gnome-keyring-daemon --start --components=pkcs11,secrets,ssh,gpg) >/dev/null 2>&1
if [[ $? -eq 0 ]] && [[ -n "$SSH_AUTH_SOCK" ]]; then
    export SSH_AUTH_SOCK
    echo "OK"
else
    echo "FAILED"
fi

# Restart Waybar
echo -n "Running: waybar ... "
killall waybar 2>/dev/null
waybar >/dev/null 2>&1 &
sleep 0.2
if pgrep -x waybar >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Restart Hyprpaper
echo -n "Running: hyprpaper ... "
killall hyprpaper 2>/dev/null
hyprpaper >/dev/null 2>&1 &
sleep 0.2
if pgrep -x hyprpaper >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Restart Hypridle
echo -n "Running: hypridle ... "
killall hypridle 2>/dev/null
hypridle >/dev/null 2>&1 &
sleep 0.2
if pgrep -x hypridle >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Restart SwayNC (notification daemon)
echo -n "Running: swaync ... "
killall swaync 2>/dev/null
swaync >/dev/null 2>&1 &
sleep 0.2
if pgrep -x swaync >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Restart SwayOSD server
echo -n "Running: swayosd-server ... "
killall swayosd-server 2>/dev/null
swayosd-server >/dev/null 2>&1 &
sleep 0.2
if pgrep -x swayosd-server >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Restart SwayOSD monitor
echo -n "Running: swayosd-monitor ... "
pkill -f swayosd-monitor.sh 2>/dev/null
bash /home/ghost/.config/scripts/swayosd-monitor.sh >/dev/null 2>&1 &
sleep 0.2
if pgrep -f swayosd-monitor.sh >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Restart battery notifier
echo -n "Running: battery-notify ... "
pkill -f battery-notify.sh 2>/dev/null
bash /home/ghost/.config/scripts/battery-notify.sh >/dev/null 2>&1 &
sleep 0.2
if pgrep -f battery-notify.sh >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Restart clipse clipboard daemon
echo -n "Running: clipse ... "
pkill -f "clipse" 2>/dev/null
clipse -listen >/dev/null 2>&1 &
sleep 0.2
if pgrep -f "clipse" >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Restart nm-applet
echo -n "Running: nm-applet ... "
killall nm-applet 2>/dev/null
nm-applet --indicator >/dev/null 2>&1 &
sleep 0.2
if pgrep -x nm-applet >/dev/null; then echo "OK"; else echo "FAILED"; fi

# Enable WiFi
echo -n "Running: nmcli radio wifi on ... "
nmcli radio wifi on >/dev/null 2>&1
if [[ $? -eq 0 ]]; then echo "OK"; else echo "FAILED"; fi

# Restart polkit agent (if service exists)
echo -n "Running: polkit agent ... "
if systemctl --user list-units --full --all | grep -q "hyprpolkitagent.service"; then
    systemctl --user restart hyprpolkitagent >/dev/null 2>&1
    sleep 0.2
    if systemctl --user is-active hyprpolkitagent >/dev/null 2>&1; then
        echo "OK"
    else
        echo "FAILED"
    fi
else
    # Service doesn't exist, check if any polkit agent is running
    if pgrep -f "polkit.*agent" >/dev/null 2>&1; then
        echo "OK (already running)"
    else
        echo "SKIPPED (no service configured)"
    fi
fi

# Run wallpaper script
echo -n "Running: wallpaper.sh ... "
bash /home/ghost/.config/scripts/wallpaper.sh >/dev/null 2>&1
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

# Stop WayVNC if running (user can restart manually with Super+Shift+V)
echo -n "Running: wayvnc ... "
if pgrep -x wayvnc >/dev/null; then
    pkill wayvnc
    echo "SKIPPED (stopped — restart with Super+Shift+V)"
else
    echo "SKIPPED (not running)"
fi

# Set app listener
echo -n "Running: hyprctl monitor fallback ... "
vicinae server >/dev/null 2>&1
if [[ $? -eq 0 ]]; then echo "OK"; else echo "FAILED"; fi

echo "======================================"
echo "Restart Complete!"
echo "======================================"
