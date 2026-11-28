#!/bin/bash
# Packages row for fastfetch (config.jsonc): fastfetch's own package counts
# plus the AppImages in Gear Lever's folder, which fastfetch does not count.

GEARLEVER_SETTINGS="$HOME/.var/app/it.mijorus.gearlever/config/glib-2.0/settings/keyfile"
GEARLEVER_DEFAULT_FOLDER="$HOME/AppImages"

folder=$(sed -n "s/^appimages-default-folder='\(.*\)'$/\1/p" "$GEARLEVER_SETTINGS" 2>/dev/null)
folder=${folder:-$GEARLEVER_DEFAULT_FOLDER}
folder=${folder/#\~/$HOME}

packages=$(fastfetch --config none --structure packages --logo none --pipe --key-type none)
appimages=$(find "$folder" -maxdepth 1 -iname '*.appimage' 2>/dev/null | wc -l)

if [ "$appimages" -gt 0 ]; then
    echo "$packages, $appimages (appimage)"
else
    echo "$packages"
fi
