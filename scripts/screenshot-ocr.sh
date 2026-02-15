#!/bin/bash

# Screenshot to text (OCR) script
# Takes a screenshot of selected area and extracts text using tesseract

# Debug log
LOG_FILE="/tmp/screenshot-ocr-debug.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== OCR Script Started: $(date) ==="

# Ensure wayland display is set
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"

# Screenshot directory
SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SCREENSHOT_DIR"

# Screenshot file (saved permanently)
SCREENSHOT="$SCREENSHOT_DIR/ocr-screenshot-$(date +%Y%m%d-%H%M%S).png"

# Take screenshot of selected area
echo -n "Taking screenshot ... "
grim -g "$(slurp)" "$SCREENSHOT"
if [[ $? -ne 0 ]]; then
    echo "FAILED"
    notify-send "Screenshot OCR" "Screenshot cancelled or failed" -u normal
    exit 1
fi
echo "OK"

# Perform OCR
echo -n "Running OCR ... "
TEXT=$(tesseract "$SCREENSHOT" - -l eng 2>/dev/null)
OCR_EXIT=$?
if [[ $OCR_EXIT -ne 0 ]]; then
    echo "FAILED"
    notify-send "Screenshot OCR" "OCR processing failed" -u critical
    exit 1
fi
echo "OK"

# Check if text was extracted
if [[ -z "$TEXT" ]]; then
    notify-send "Screenshot OCR" "No text found in screenshot" -u normal
    rm -f "$SCREENSHOT"
    exit 0
fi

# Copy to clipboard (using echo -n to avoid trailing newline)
echo -n "Copying to clipboard ... "
echo -n "$TEXT" | /usr/bin/wl-copy 2>/dev/null
sleep 0.5
echo "OK"

# Add to clipboard manager
echo -n "Adding to clipboard history ... "
echo -n "$TEXT" | /usr/bin/cliphist store 2>/dev/null
sleep 0.2
echo "OK"

# Show notification with preview (first 100 chars)
PREVIEW=$(echo "$TEXT" | head -c 100)
if [[ ${#TEXT} -gt 100 ]]; then
    PREVIEW="${PREVIEW}..."
fi
notify-send "Screenshot OCR" "Text copied!\n\n$PREVIEW" -u normal -t 5000

echo "Screenshot saved: $SCREENSHOT"
echo "Text length: ${#TEXT} characters"
