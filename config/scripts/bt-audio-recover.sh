#!/bin/bash
# bt-audio-recover.sh — move a connected Bluetooth headset off the "off" audio profile.
#
# A headset can connect and still sit on the card profile "off" (seen with
# AirPods after a reconnect): bluetoothctl says Connected, but PipeWire has no
# output for it. WirePlumber normally picks a profile on its own, so on every
# card event wait for it to settle and only then, if the card is still off, set
# a2dp-sink. Runs as the bt-audio-recover user unit (see restart.sh).
#
# Usage:
#   bt-audio-recover.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"

readonly SETTLE_SECONDS=5
readonly PROFILE=a2dp-sink

# Connected Bluetooth cards on the "off" profile, as "<card name><TAB><description>".
stuck_cards() {
    pactl --format=json list cards 2>/dev/null | jq -r '
        .[]
        | select(.name | startswith("bluez_card."))
        | select(.active_profile == "off" and .properties["api.bluez5.connection"] == "connected")
        | [.name, .properties["device.description"]] | @tsv'
}

recover() {
    local card description
    while IFS=$'\t' read -r card description; do
        if pactl set-card-profile "$card" "$PROFILE"; then
            notify low bt-audio-recover bluetooth "Bluetooth audio" "${description:-$card} had no audio profile, switched to A2DP"
        else
            echo "bt-audio-recover: could not set $PROFILE on $card" >&2
        fi
    done < <(stuck_cards)
}

settle_then_recover() {
    sleep "$SETTLE_SECONDS"
    recover
}

# A headset may already be stuck when the session starts. `pending` is the check
# waiting out the settle time; a newer card event restarts it, so a burst of
# events (connect, route and profile changes) causes one check after the last.
settle_then_recover &
pending=$!

# Lines look like: Event 'change' on card #423
pactl subscribe | while read -r _ event _ kind _; do
    [[ $kind == card && ($event == "'new'" || $event == "'change'") ]] || continue
    kill "$pending" 2>/dev/null
    settle_then_recover &
    pending=$!
done

# pactl subscribe only ends when the sound server goes away; exit non-zero so
# systemd restarts this once it is back.
echo "bt-audio-recover: lost the sound server" >&2
exit 1
