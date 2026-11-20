#!/bin/bash
# Generates an initials avatar and sets it as the user's picture through
# AccountsService (SetIconFile over D-Bus; polkit lets a user change their
# own picture, so no sudo). AccountsService copies it to
# /var/lib/AccountsService/icons/<user>, which ~/.config/hypr/avatar.png
# points at. Used by dots.sh setup and the settings app (Users).
set -euo pipefail

USER_NAME=$(whoami)
INITIAL="${USER_NAME:0:1}"

# A private temporary file, not a fixed name in the shared /tmp that another
# user could create first.
TMP_PNG=$(mktemp --suffix=.png)
trap 'rm -f "$TMP_PNG"' EXIT

python3 - "$TMP_PNG" <<PYEOF
from PIL import Image, ImageDraw, ImageFont
import os
import sys

initial = "${INITIAL}".upper()
size = 256
img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

draw.ellipse([0, 0, size-1, size-1], fill=(28, 25, 23, 255))

font = None
for path in [
    "/usr/share/fonts/google-carlito-fonts/Carlito-Bold.ttf",
    "/usr/share/fonts/google-noto/NotoSans-Bold.ttf",
    "/usr/share/fonts/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/google-droid-sans-fonts/DroidSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
]:
    if os.path.exists(path):
        font = ImageFont.truetype(path, 170)
        break

if font is None:
    font = ImageFont.load_default()

bbox = draw.textbbox((0, 0), initial, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
draw.text(((size - tw) / 2 - bbox[0], (size - th) / 2 - bbox[1]), initial, font=font, fill=(245, 245, 244, 230))

img.save(sys.argv[1], "PNG")
PYEOF

USER_PATH=$(busctl call org.freedesktop.Accounts /org/freedesktop/Accounts \
    org.freedesktop.Accounts FindUserByName s "$USER_NAME" | awk '{print $2}' | tr -d '"')
busctl call org.freedesktop.Accounts "$USER_PATH" org.freedesktop.Accounts.User SetIconFile s "$TMP_PNG"
echo "Avatar set for $USER_NAME"
