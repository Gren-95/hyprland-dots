#!/bin/bash

SCREENSHOT_DIR="$HOME/Pictures/Screenshots/ocr"
mkdir -p "$SCREENSHOT_DIR"
SCREENSHOT="$SCREENSHOT_DIR/ocr-$(date +%Y%m%d-%H%M%S).png"

grim -g "$(slurp)" "$SCREENSHOT" || exit 0

# Preprocess: upscale 3x for better diacritic recognition,
# auto-invert if background is dark (mean brightness < 0.5)
PROC="${SCREENSHOT%.png}-proc.png"
MEAN=$(convert "$SCREENSHOT" -colorspace Gray -format "%[fx:mean]" info: 2>/dev/null)
if (( $(echo "${MEAN:-0.5} < 0.5" | bc -l) )); then
    convert "$SCREENSHOT" -resize 300% -colorspace Gray -negate -contrast-stretch 1% "$PROC"
else
    convert "$SCREENSHOT" -resize 300% -colorspace Gray -contrast-stretch 1% "$PROC"
fi

TEXT=$(tesseract "$PROC" stdout -l eng+est --oem 1 2>/dev/null)
rm -f "$PROC"

if [[ -z "${TEXT//[[:space:]]/}" ]]; then
    notify-send "Screenshot OCR" "No text found" -u normal
    rm -f "$SCREENSHOT"
    exit 0
fi


PREVIEW="${TEXT:0:100}"
[[ ${#TEXT} -gt 100 ]] && PREVIEW+="..."
notify-send "Screenshot OCR" "Copied: $PREVIEW" -t 5000

printf '%s' "$TEXT" | wl-copy
