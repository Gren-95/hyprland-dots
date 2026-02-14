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

# Copy to clipboard and clipboard manager
echo -n "Copying to clipboard ... "
printf "%s" "$TEXT" | tee >(wl-copy --type text/plain) | cliphist store
sleep 0.5
echo "OK"

# Show notification with preview (first 100 chars)
PREVIEW=$(echo "$TEXT" | head -c 100)
if [[ ${#TEXT} -gt 100 ]]; then
    PREVIEW="${PREVIEW}..."
fi
notify-send "Screenshot OCR" "Text copied to clipboard!\nScreenshot saved to:\n$SCREENSHOT\n\n$PREVIEW" -u normal -t 5000

echo "Screenshot saved: $SCREENSHOT"
echo "Text length: ${#TEXT} characters"
