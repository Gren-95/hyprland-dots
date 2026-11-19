#!/bin/bash
# games.sh - Installed games for the launcher's Games view.
#
# Usage: games.sh list
#   Prints a JSON array of Steam games installed in any library:
#   [{"id": "steam:489830", "name": "…", "appid": "489830", "art": "/path/cover.jpg"}]
#   Proton, the Steam Linux Runtime and other tools Steam installs as apps
#   are left out. "art" is the library cover (or the header picture) from
#   Steam's cache, empty when there is none. Apps in the Game category come
#   from their desktop entries in Quickshell, not from here.
set -euo pipefail

STEAM="${XDG_DATA_HOME:-$HOME/.local/share}/Steam"
CACHE="$STEAM/appcache/librarycache"
TOOLS='^(Proton |Proton$|Steam Linux Runtime|Steamworks Common Redistributables|Steamworks Shared)'

# The value of "key" in a VDF/ACF file.
vdf_value() { sed -nE "s/^[[:space:]]*\"$1\"[[:space:]]+\"(.*)\"[[:space:]]*$/\1/p" "$2" | head -n1; }

libraries() {
    local vdf="$STEAM/steamapps/libraryfolders.vdf"
    [[ -f "$vdf" ]] || return 0
    sed -nE 's/^[[:space:]]*"path"[[:space:]]+"(.*)"[[:space:]]*$/\1/p' "$vdf"
}

cover() {
    local dir="$CACHE/$1" file found
    [[ -d "$dir" ]] || return 0
    # The cover, else the header picture; newer Steam keeps them one folder
    # deeper (under a hash) and names the cover library_capsule.jpg.
    for file in library_600x900.jpg library_capsule.jpg header.jpg library_header.jpg; do
        found=$(find "$dir" -maxdepth 2 -name "$file" -print -quit 2>/dev/null)
        [[ -n "$found" ]] && {
            echo "$found"
            return
        }
    done
}

list() {
    local lib manifest appid name
    {
        while IFS= read -r lib; do
            for manifest in "$lib"/steamapps/appmanifest_*.acf; do
                [[ -f "$manifest" ]] || continue
                appid=$(vdf_value appid "$manifest")
                name=$(vdf_value name "$manifest")
                [[ -n "$appid" && -n "$name" ]] || continue
                [[ "$name" =~ $TOOLS ]] && continue
                jq -n --arg appid "$appid" --arg name "$name" --arg art "$(cover "$appid")" \
                    '{id: ("steam:" + $appid), appid: $appid, name: $name, art: $art}'
            done
        done < <(libraries)
    } | jq -s 'unique_by(.appid) | sort_by(.name | ascii_downcase)'
}

case "${1:-}" in
    list) list ;;
    *)
        echo "usage: $0 list" >&2
        exit 2
        ;;
esac
