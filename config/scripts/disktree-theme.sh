#!/bin/bash
# disktree-theme.sh — give Disktree (the treemap disk analyzer) the shell palette.
#
# Disktree is built on gpui-omarchy, which reads Omarchy's current theme from
# ~/.local/state/omarchy/current/theme/colors.toml. This is not Omarchy, so
# that file does not exist and Disktree would fall back to a stock palette.
# Write it from quickshell/Theme.qml instead. A running Disktree picks up the
# change on its own; run this again after editing the palette.
#
# Usage:
#   disktree-theme.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

readonly THEME_QML="$CONFIG_DIR/quickshell/Theme.qml"
readonly CURRENT_DIR="$HOME/.local/state/omarchy/current"
readonly THEME_NAME="Stone"

# The hex value of `readonly property color <name>: "#rrggbb"` in Theme.qml.
# Names are unique across the top-level surfaces and the accent object.
qml_color() {
    local hex
    hex=$(grep -oP "readonly property color $1:\s*\"\K#[0-9a-fA-F]{6}" "$THEME_QML" | head -n 1)
    if [[ -z $hex ]]; then
        echo "disktree-theme: no color '$1' in $THEME_QML" >&2
        exit 1
    fi
    printf '%s' "${hex,,}"
}

[[ -f $THEME_QML ]] || {
    echo "disktree-theme: $THEME_QML not found" >&2
    exit 1
}

mkdir -p "$CURRENT_DIR/theme"

# Written to a temp file and renamed: Disktree watches the file, and a half
# written palette would make it drop back to its stock colors.
tmp=$(mktemp "$CURRENT_DIR/theme/.colors.XXXXXX")
trap 'rm -f "$tmp"' EXIT
cat >"$tmp" <<EOF
mode = "dark"

accent = "$(qml_color orange)"
selection = "$(qml_color bgActive)"
muted = "$(qml_color borderStrong)"

background = "$(qml_color bg)"
dark_background = "$(qml_color bgDeep)"
lighter_background = "$(qml_color bgAlt)"

foreground = "$(qml_color fgDim)"
bright_foreground = "$(qml_color fg)"

red = "$(qml_color red)"
yellow = "$(qml_color yellow)"
orange = "$(qml_color orange)"
green = "$(qml_color green)"
cyan = "$(qml_color teal)"
blue = "$(qml_color blue)"
magenta = "$(qml_color purple)"
EOF
chmod 644 "$tmp"
mv -f "$tmp" "$CURRENT_DIR/theme/colors.toml"
printf '%s\n' "$THEME_NAME" >"$CURRENT_DIR/theme.name"
echo "Wrote $CURRENT_DIR/theme/colors.toml"
