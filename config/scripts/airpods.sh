#!/bin/bash
# AirPods controls for the Bluetooth flyout (quickshell/AirPodsControls.qml).
#
# Usage:
#   airpods.sh mode <off|anc|transparency|adaptive>   noise control (via librepods)
#   airpods.sh conversation <on|off>                   conversation awareness (via librepods)
#   airpods.sh codec <MAC> <aac|sbc-xq|sbc>            A2DP codec for the AirPods card
#   airpods.sh codec-status <MAC>                      print the active card profile
#   airpods.sh reset-audio <MAC>                       drop and restore the audio profile
#
# Noise control and conversation awareness go to the patched librepods daemon
# over $XDG_RUNTIME_DIR/librepods.sock (see librepods/control-socket.patch).
# reset-audio switches the card off and back to its A2DP profile, which brings
# back a bud that went silent while the other kept playing.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

SOCKET="$RUNTIME_DIR/librepods.sock"

send() {
    if [[ ! -S $SOCKET ]]; then
        echo "airpods.sh: librepods is not running (no $SOCKET)" >&2
        exit 1
    fi
    python3 -c 'import socket, sys
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
s.sendall((sys.argv[2] + "\n").encode())
s.close()' "$SOCKET" "$1"
}

card_for() {
    echo "bluez_card.${1//:/_}"
}

profile_for() {
    case $1 in
        aac) echo a2dp-sink ;;
        sbc-xq) echo a2dp-sink-sbc_xq ;;
        sbc) echo a2dp-sink-sbc ;;
        *)
            echo "airpods.sh: unknown codec $1" >&2
            exit 2
            ;;
    esac
}

case ${1:-} in
    mode)
        case ${2:-} in
            off) send "listening-mode 1" ;;
            anc) send "listening-mode 2" ;;
            transparency) send "listening-mode 3" ;;
            adaptive) send "listening-mode 4" ;;
            *)
                echo "usage: airpods.sh mode off|anc|transparency|adaptive" >&2
                exit 2
                ;;
        esac
        ;;
    conversation)
        [[ ${2:-} == on || ${2:-} == off ]] || {
            echo "usage: airpods.sh conversation on|off" >&2
            exit 2
        }
        send "conversation-detect $2"
        ;;
    codec)
        pactl set-card-profile "$(card_for "${2:?MAC}")" "$(profile_for "${3:?codec}")"
        ;;
    codec-status)
        pactl list cards | awk -v card="$(card_for "${2:?MAC}")" '
            $1 == "Name:" { inside = ($2 == card) }
            inside && /Active Profile:/ { print $3; exit }'
        ;;
    reset-audio)
        card=$(card_for "${2:?MAC}")
        profile=$(bash "$0" codec-status "$2")
        [[ $profile == a2dp-sink* ]] || profile=a2dp-sink
        pactl set-card-profile "$card" off
        sleep 1
        pactl set-card-profile "$card" "$profile"
        ;;
    *)
        sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//' >&2
        exit 2
        ;;
esac
