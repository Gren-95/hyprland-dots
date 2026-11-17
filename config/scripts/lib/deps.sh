#!/bin/bash
# deps.sh — single source of truth for the commands the dotfiles depend on.
# Used by dots.sh setup (install) and doctor.sh (verify).
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
    grim slurp swappy wl-copy wl-paste cliphist tesseract convert magick bc
    firefox brightnessctl playerctl powerprofilesctl upower mpv
    gpu-screen-recorder inotifywait gnome-keyring-daemon nm-applet nmcli
    notify-send busctl gsettings jq curl pactl wpctl bluetoothctl python3 fish ranger
    hyprshutdown timeshift fzf gnome-font-viewer
)

DEPS_OPTIONAL=(
    wayvnc               # scripts/wayvnc-toggle.sh
    tailscale            # wayvnc binding address
    hyprsunset           # scripts/night.sh
    unzip                # scripts/extract.sh, thumbnailers/3mf.thumbnailer
    gnome-thumbnail-font # font thumbnails, also thumbnailers/woff2.thumbnailer
    expect               # scripts/ledvance.sh
    immich               # scripts/immich-sync.sh
    crontab              # sync-toggle.sh (immich schedule)
    docker               # scripts/games-browser-toggle.sh, winvm-toggle.sh, gamemode.sh
    evtest               # quickshell/SuperWatch.qml (falls back to a timer without it)
    zoxide               # fish/config.fish (skipped when missing)
    disktree             # scripts/disktree.sh, fish disktree function
)

DEPS_DNF=(
    hyprland hyprland-devel quickshell kitty nautilus cliphist
    awww hyprpicker hypridle hyprlock grim slurp
    swappy tesseract tesseract-langpack-est ImageMagick wl-clipboard firefox
    brightnessctl playerctl powerprofilesctl gpu-screen-recorder
    network-manager-applet libnotify upower mpv bc curl
    gnome-keyring jq inotify-tools pulseaudio-utils bluez hyprshutdown timeshift fzf gnome-font-viewer
    fish ranger python3 python3-pillow python3-numpy python3-gobject unzip liberation-sans-fonts
)

# Print the required commands that are not on PATH, one per line.
deps_missing_required() {
    local dep
    for dep in "${DEPS_REQUIRED[@]}"; do
        command -v "$dep" >/dev/null 2>&1 || echo "$dep"
    done
}

# Exit 0 when python3 can import PyGObject (idle inhibit helpers need it).
deps_have_pygobject() {
    python3 -c 'import gi' >/dev/null 2>&1
}
