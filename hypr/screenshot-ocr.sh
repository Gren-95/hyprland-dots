#!/bin/bash

# Screenshot to text (OCR) script
# Takes a screenshot of selected area and extracts text using tesseract

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
TEXT=$(tesseract "$SCREENSHOT" - -l eng 2>&1)
OCR_EXIT=$?
if [[ $OCR_EXIT -ne 0 ]]; then
    echo "FAILED"
    notify-send "Screenshot OCR" "OCR processing failed:\n$TEXT" -u critical
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
printf "%s" "$TEXT" | wl-copy
COPY_EXIT=$?
if [[ $COPY_EXIT -eq 0 ]]; then
    echo "OK"
    # Show notification with preview (first 100 chars)
    PREVIEW=$(echo "$TEXT" | head -c 100)
    if [[ ${#TEXT} -gt 100 ]]; then
        PREVIEW="${PREVIEW}..."
    fi
    notify-send "Screenshot OCR" "Text copied to clipboard!\nScreenshot saved to:\n$SCREENSHOT\n\n$PREVIEW" -u normal
else
    echo "FAILED"
    notify-send "Screenshot OCR" "Failed to copy text to clipboard" -u critical
fi

echo "Screenshot saved: $SCREENSHOT"
