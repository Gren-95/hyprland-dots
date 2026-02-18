#!/bin/bash

SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SCREENSHOT_DIR"
SCREENSHOT="$SCREENSHOT_DIR/ocr-$(date +%Y%m%d-%H%M%S).png"

grim -g "$(slurp)" "$SCREENSHOT" || exit 0

TEXT=$(tesseract "$SCREENSHOT" stdout 2>/dev/null)

if [[ -z "${TEXT//[[:space:]]/}" ]]; then
    notify-send "Screenshot OCR" "No text found" -u normal
    rm -f "$SCREENSHOT"
    exit 0
fi


PREVIEW="${TEXT:0:100}"
[[ ${#TEXT} -gt 100 ]] && PREVIEW+="..."
notify-send "Screenshot OCR" "Copied: $PREVIEW" -t 5000

printf '%s' "$TEXT" | wl-copy
