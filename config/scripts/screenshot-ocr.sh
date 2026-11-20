#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/settings.sh"

fail() {
    notify normal screenshot-ocr dialog-error "Screenshot OCR" "$1"
    exit 1
}

command -v tesseract >/dev/null || fail "Text recognition needs Tesseract (tesseract), which is not installed"

# The languages picked in the settings app (Screenshots & recording), as
# "eng+est"; every installed one when none is picked. A picked language that
# was uninstalled since is dropped.
installed=$(tesseract --list-langs 2>/dev/null | tail -n +2 | grep -vx osd | paste -sd+ || true)
[[ -n $installed ]] || fail "No Tesseract language is installed (for English: tesseract-langpack-eng)"
picked=$(valid "$(setting ocr-languages "$installed")" '[a-z_]+(\+[a-z_]+)*' "$installed")
LANGS=$(tr '+' '\n' <<<"$picked" | grep -Fxf <(tr '+' '\n' <<<"$installed") | paste -sd+ || true)
LANGS=${LANGS:-$installed}

mkdir -p "$OCR_DIR"
SCREENSHOT="$OCR_DIR/ocr-$(date +%Y%m%d-%H%M%S).png"

# If a file path is given as $1, OCR that image instead of grabbing a new
# region. Used by the Screenshot Actions modal to re-OCR a captured shot.
if [[ $# -ge 1 && -f "$1" ]]; then
    cp "$1" "$SCREENSHOT"
else
    grim -g "$(slurp)" "$SCREENSHOT" || exit 0
fi

# Preprocess: upscale 3x for better diacritic recognition,
# auto-invert if background is dark (mean brightness < 0.5)
PROC="${SCREENSHOT%.png}-proc.png"
trap 'rm -f "$PROC"' EXIT
MEAN=$(convert "$SCREENSHOT" -colorspace Gray -format "%[fx:mean]" info: 2>/dev/null)
if (($(echo "${MEAN:-0.5} < 0.5" | bc -l))); then
    convert "$SCREENSHOT" -resize 300% -colorspace Gray -negate -contrast-stretch 1% "$PROC"
else
    convert "$SCREENSHOT" -resize 300% -colorspace Gray -contrast-stretch 1% "$PROC"
fi

TEXT=$(tesseract "$PROC" stdout -l "$LANGS" --oem 1 2>/dev/null) || {
    rm -f "$SCREENSHOT"
    fail "Could not read the text"
}

if [[ -z "${TEXT//[[:space:]]/}" ]]; then
    notify normal screenshot-ocr edit-find "Screenshot OCR" "No text found"
    rm -f "$SCREENSHOT"
    exit 0
fi

PREVIEW="${TEXT:0:100}"
[[ ${#TEXT} -gt 100 ]] && PREVIEW+="..."
notify normal screenshot-ocr edit-find "Screenshot OCR" "Copied: $PREVIEW" 5000

printf '%s' "$TEXT" | wl-copy
