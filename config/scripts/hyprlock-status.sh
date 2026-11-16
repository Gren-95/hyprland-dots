#!/bin/bash
# Text sources for hyprlock labels. Usage: hyprlock-status.sh battery|title|artist
#
# These live in a script because hyprlock.conf cannot hold them inline:
# hyprlang evaluates "{{ }}" as an arithmetic expression, so a playerctl
# --format string there turns the label into "Sample Text".
#
# Every mode prints nothing when there is nothing to show (no battery, no
# player), always exits 0 and keeps stderr clean, because hyprlock logs
# stderr output as an error.

MAX_CHARS=42

battery() {
    local bat capacity status icon idx
    bat=$(find /sys/class/power_supply -maxdepth 1 -name 'BAT*' 2>/dev/null | head -n1)
    [[ -n $bat && -r $bat/capacity ]] || return

    capacity=$(<"$bat/capacity")
    status=$(<"$bat/status")

    if [[ $status == Charging || $status == Full ]]; then
        icon="󰂄"
    elif ((capacity <= 15)); then
        icon="󰂃"
    else
        # 󰁺..󰁹 is the 10%..100% glyph range in Nerd Fonts.
        local icons=(󰁺 󰁻 󰁼 󰁽 󰁾 󰁿 󰂀 󰂁 󰂂 󰁹)
        idx=$(((capacity - 1) / 10))
        ((idx < 0)) && idx=0
        ((idx > 9)) && idx=9
        icon=${icons[idx]}
    fi

    printf '%s  %s%%\n' "$icon" "$capacity"
}

# Prints one MPRIS field, cut to MAX_CHARS characters with an ellipsis.
media_field() {
    local value
    value=$(playerctl metadata "$1" 2>/dev/null) || return
    if ((${#value} > MAX_CHARS)); then
        value="${value:0:MAX_CHARS-1}…"
    fi
    printf '%s\n' "$value"
}

case ${1:-} in
    battery) battery ;;
    title) media_field title ;;
    artist) media_field artist ;;
esac
exit 0
