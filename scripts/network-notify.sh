#!/bin/bash
# network-notify.sh — Notify on network connect/disconnect events
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"

nmcli monitor 2>/dev/null | while read -r line; do
    case "$line" in
        *": connected to "*)
            iface="${line%%:*}"
            ssid="${line#*connected to }"
            notify normal network network-wireless "Connected" "${ssid} (${iface})"
            ;;
        *": disconnected"*)
            iface="${line%%:*}"
            notify normal network network-wireless-offline "Disconnected" "${iface} disconnected"
            ;;
    esac
done
