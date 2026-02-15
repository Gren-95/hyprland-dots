#!/bin/bash
# Monitor PipeWire volume changes and trigger SwayOSD
# This makes SwayOSD react to ALL volume changes, not just media keys

LAST_VOLUME=""

# Function to trigger OSD display
trigger_osd() {
    # Get current volume
    VOLUME_INFO=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)

    if [[ -z "$VOLUME_INFO" ]]; then
        return
    fi

    # Only trigger if volume actually changed
    if [[ "$VOLUME_INFO" == "$LAST_VOLUME" ]]; then
        return
    fi

    LAST_VOLUME="$VOLUME_INFO"

    # Trigger swayosd by doing a +0% change (shows OSD without changing volume)
    # This is a workaround since swayosd doesn't have a "display only" mode
    swayosd-client --output-volume +0 2>/dev/null || true
}

# Subscribe to PipeWire sink events
pactl subscribe 2>/dev/null | grep --line-buffered "sink" | while read -r event; do
    trigger_osd
done
