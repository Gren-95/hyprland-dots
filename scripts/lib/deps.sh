#!/bin/bash
# deps.sh — single source of truth for the commands the dotfiles depend on.
# Used by setup.sh (install) and doctor.sh (verify).
#
# Source it:
#   source "<repo>/scripts/lib/deps.sh"
#
# DEPS_REQUIRED   commands that must exist for the session to work
# DEPS_OPTIONAL   commands only some scripts/features need
# DEPS_DNF        dnf packages that provide DEPS_REQUIRED (+ python3-gobject)
#
# Derived from the commands scripts/*.sh and hypr/modules/*.lua actually run.
# shellcheck disable=SC2034  # arrays are consumed by the sourcing script

DEPS_REQUIRED=(
    hyprland hyprctl qs kitty nautilus awww awww-daemon hyprpicker hypridle hyprlock
    grim slurp swappy wl-copy wl-paste cliphist tesseract convert bc
    firefox brightnessctl playerctl powerprofilesctl upower mpv
    gpu-screen-recorder inotifywait gnome-keyring-daemon nm-applet nmcli
    notify-send busctl gsettings jq curl pactl wpctl python3 fish ranger
)

DEPS_OPTIONAL=(
    wayvnc     # scripts/wayvnc-toggle.sh
    tailscale  # wayvnc binding address
    hyprsunset # scripts/night.sh
    magick     # scripts/gallery-shots.sh (ImageMagick 7)
    unzip      # scripts/extract.sh
    expect     # scripts/ledvance.sh
    immich     # scripts/immich-sync.sh
    crontab    # sync-toggle.sh (immich schedule)
)

DEPS_DNF=(
    hyprland hyprland-devel quickshell kitty nautilus cliphist
    awww hyprpicker hypridle hyprlock grim slurp
    swappy tesseract tesseract-langpack-est ImageMagick wl-clipboard firefox
    brightnessctl playerctl powerprofilesctl gpu-screen-recorder
    network-manager-applet libnotify upower mpv bc curl
    gnome-keyring jq inotify-tools
    fish ranger python3 python3-pillow python3-gobject
)

# Print the required commands that are not on PATH, one per line.
deps_missing_required() {
    local dep
    for dep in "${DEPS_REQUIRED[@]}"; do
        command -v "$dep" >/dev/null 2>&1 || echo "$dep"
    done
}

# Exit 0 when python3 can import PyGObject (media/idle inhibitors need it).
deps_have_pygobject() {
    python3 -c 'import gi' >/dev/null 2>&1
}
