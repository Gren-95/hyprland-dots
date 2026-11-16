#!/bin/bash
# Prints the current weather for the hyprlock corner, e.g. "󰖐  3°  overcast",
# with the glyph coloured as pango markup.
#
# Reads the same settings as quickshell's WeatherService (weather-location,
# weather-fahrenheit) and asks the same keyless open-meteo API, mapping the
# WMO codes to the same glyphs, labels and accent colours.
#
# The last good reading is cached, so the lock screen still shows something
# right after resume when the network is not back yet. Readings older than
# STALE_SECONDS are dropped rather than shown as current.
#
# Prints nothing when weather is off (empty location) or nothing usable is
# known. Always exits 0 and keeps stderr clean, because hyprlock logs stderr
# output as an error.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

SETTINGS_DIR="$HOME/.config/quickshell/settings"
CACHE="$CACHE_DIR/hyprlock-weather"
GEO_CACHE="$CACHE_DIR/hyprlock-weather-geo"
STALE_SECONDS=10800

location=$(cat "$SETTINGS_DIR/weather-location" 2>/dev/null) || location=""
location=$(printf '%s' "$location" | xargs 2>/dev/null)
[[ -n $location ]] || exit 0

fahrenheit=$(cat "$SETTINGS_DIR/weather-fahrenheit" 2>/dev/null) || fahrenheit=0
unit=celsius
[[ $fahrenheit == 1 || $fahrenheit == true ]] && unit=fahrenheit

show_cache() {
    [[ -s $CACHE ]] || exit 0
    local age=$(($(date +%s) - $(stat -c %Y "$CACHE")))
    ((age <= STALE_SECONDS)) && cat "$CACHE"
    exit 0
}

# Geocoding: cached per location name, so only a location change refetches.
coords=""
if [[ -s $GEO_CACHE ]]; then
    IFS=$'\t' read -r geo_name geo_coords <"$GEO_CACHE"
    [[ $geo_name == "$location" ]] && coords=$geo_coords
fi
if [[ -z $coords ]]; then
    coords=$(curl -fsSL --max-time 8 -G \
        --data-urlencode "name=$location" --data "count=1" \
        https://geocoding-api.open-meteo.com/v1/search 2>/dev/null |
        jq -r '.results[0] | "\(.latitude),\(.longitude)"' 2>/dev/null) || coords=""
    [[ $coords =~ ^-?[0-9.]+,-?[0-9.]+$ ]] || show_cache
    printf '%s\t%s\n' "$location" "$coords" >"$GEO_CACHE"
fi

read -r code temp is_day < <(curl -fsSL --max-time 8 \
    "https://api.open-meteo.com/v1/forecast?latitude=${coords%,*}&longitude=${coords#*,}&current=temperature_2m,weather_code,is_day&temperature_unit=$unit" \
    2>/dev/null | jq -r '.current | "\(.weather_code) \(.temperature_2m) \(.is_day)"' 2>/dev/null)
[[ ${code:-} =~ ^[0-9]+$ && ${temp:-} =~ ^-?[0-9.]+$ ]] || show_cache

# Mirrors WeatherService.qml glyphFor / labelFor / colorFor.
# Colours are Theme.accent: yellow, purple, blueBright, slate, teal, blue.
day=$((is_day == 1))
if ((code == 0)); then
    glyph=$( ((day)) && echo 󰖙 || echo 󰖔)
    label="clear"
    color=$( ((day)) && echo '#ffc531' || echo '#b57bff')
elif ((code <= 2)); then
    glyph=$( ((day)) && echo 󰖕 || echo 󰼱)
    label="partly cloudy"
    color=$( ((day)) && echo '#6fb0ff' || echo '#b57bff')
elif ((code == 3)); then
    glyph=󰖐
    label="overcast"
    color='#94a3b8'
elif ((code <= 48)); then
    glyph=󰖑
    label="fog"
    color='#94a3b8'
elif ((code <= 57)); then
    glyph=󰖗
    label="drizzle"
    color='#2ee6d6'
elif ((code <= 67 || (code >= 80 && code <= 82))); then
    glyph=󰖖
    label="rain"
    color='#4c9aff'
elif ((code <= 77 || code == 85 || code == 86)); then
    glyph=󰖘
    label="snow"
    color='#6fb0ff'
else
    glyph=󰖓
    label="thunderstorm"
    color='#b57bff'
fi

# LC_ALL=C: a locale with a decimal comma (et_EE) rejects "3.9".
LC_ALL=C printf -v rounded '%.0f' "$temp"
line="<span foreground='$color'>$glyph</span>  $rounded°  $label"
printf '%s\n' "$line" >"$CACHE.tmp" && mv -f "$CACHE.tmp" "$CACHE"
printf '%s\n' "$line"
exit 0
