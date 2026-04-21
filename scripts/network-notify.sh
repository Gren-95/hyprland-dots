#!/bin/bash
# network-notify.sh — Notify on network connect/disconnect events

nmcli monitor 2>/dev/null | while read -r line; do
    case "$line" in
        *": connected to "*)
            iface="${line%%:*}"
            ssid="${line#*connected to }"
            notify-send -u normal -i network-wireless "Connected" "${ssid} (${iface})"
            ;;
        *": disconnected"*)
            iface="${line%%:*}"
            notify-send -u normal -i network-wireless-offline "Disconnected" "${iface} disconnected"
            ;;
    esac
done
