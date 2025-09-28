#!/usr/bin/env bash

# Two-way clipboard synchronization between Wayland and X11
# This helps with drag and drop functionality

# Check if required tools are available
command -v wl-paste >/dev/null 2>&1 || { echo "wl-paste not found. Please install wl-clipboard."; exit 1; }
command -v xclip >/dev/null 2>&1 || { echo "xclip not found. Please install xclip."; exit 1; }

# Function to sync clipboard content
sync_clipboard() {
    # Get current clipboard content from both sources
    wl_content=$(wl-paste -n 2>/dev/null | tr -d '\0' | head -c 1000 || echo "")
    x_content=$(xclip -o -selection clipboard 2>/dev/null | tr -d '\0' | head -c 1000 || echo "")
    
    # If Wayland clipboard is different from X11, update X11
    if [ "$wl_content" != "$x_content" ] && [ -n "$wl_content" ]; then
        echo -n "$wl_content" | xclip -selection clipboard 2>/dev/null
        # Also store in cliphist if available
        command -v cliphist >/dev/null 2>&1 && echo -n "$wl_content" | cliphist store
    fi
    
    # If X11 clipboard is different from Wayland, update Wayland
    if [ "$x_content" != "$wl_content" ] && [ -n "$x_content" ]; then
        echo -n "$x_content" | wl-copy 2>/dev/null
        # Also store in cliphist if available
        command -v cliphist >/dev/null 2>&1 && echo -n "$x_content" | cliphist store
    fi
}

# Watch for clipboard changes
{
    wl-paste --watch sync_clipboard &
    while true; do
        sync_clipboard
        sleep 1
    done
} &

# Keep the script running
wait 