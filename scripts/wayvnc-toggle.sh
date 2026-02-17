#!/bin/bash
if pgrep -x wayvnc > /dev/null; then
    pkill wayvnc
    notify-send -i network-vpn "WayVNC" "Remote access stopped"
else
    wayvnc &>/dev/null &
    sleep 0.5
    IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    notify-send -i network-vpn "WayVNC" "Remote access started\n${IP}:5900"
fi
