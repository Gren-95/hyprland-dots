#!/bin/bash

# Start gnome-keyring-daemon and export SSH_AUTH_SOCK
echo -n "Running: Start gnome-keyring-daemon ... "
eval $(/usr/bin/gnome-keyring-daemon --start --components=pkcs11,secrets,ssh,gpg) >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
    echo "OK"
else
    echo "FAILED"
fi

echo -n "Running: Export SSH_AUTH_SOCK ... "
if [[ -n "$SSH_AUTH_SOCK" ]]; then
    export SSH_AUTH_SOCK="$SSH_AUTH_SOCK"
    echo "OK"
else
    echo "FAILED"
fi
killall waybar 
waybar &
killall swaync
swaync &
killall swayosd
swayosd-server &
killall nm-applet
nm-applet --indicator &
killall clipse
clipse -listen &

systemctl --user start hyprpolkitagent

killall hyprpaper
hyprpaper &


#run_cmd "Start menu" bash -c "$menu" >/dev/null 2>&1 &