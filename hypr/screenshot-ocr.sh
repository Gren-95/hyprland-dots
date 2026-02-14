#!/bin/bash

# Screenshot to text (OCR) script
# Takes a screenshot of selected area and extracts text using tesseract

# Create temp directory if it doesn't exist
TEMP_DIR="/tmp/screenshot-ocr"
mkdir -p "$TEMP_DIR"

# Temp file for screenshot
SCREENSHOT="$TEMP_DIR/screenshot-$(date +%s).png"

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
TEXT=$(tesseract "$SCREENSHOT" - 2>/dev/null)
if [[ $? -ne 0 ]]; then
    echo "FAILED"
    notify-send "Screenshot OCR" "OCR processing failed" -u critical
    rm -f "$SCREENSHOT"
    exit 1
fi
echo "OK"

# Check if text was extracted
if [[ -z "$TEXT" ]]; then
    notify-send "Screenshot OCR" "No text found in screenshot" -u normal
    rm -f "$SCREENSHOT"
    exit 0
fi

# Copy to clipboard
echo -n "Copying to clipboard ... "
echo -n "$TEXT" | wl-copy
if [[ $? -eq 0 ]]; then
    echo "OK"
    # Show notification with preview (first 100 chars)
    PREVIEW=$(echo "$TEXT" | head -c 100)
    if [[ ${#TEXT} -gt 100 ]]; then
        PREVIEW="${PREVIEW}..."
    fi
    notify-send "Screenshot OCR" "Text copied to clipboard:\n\n$PREVIEW" -u normal
else
    echo "FAILED"
    notify-send "Screenshot OCR" "Failed to copy text to clipboard" -u critical
fi

# Cleanup
rm -f "$SCREENSHOT"

# Clean up old temp files (older than 1 hour)
find "$TEMP_DIR" -name "screenshot-*.png" -mmin +60 -delete 2>/dev/null
