#!/bin/bash
# Builds LibrePods (Rust rewrite) at the pinned commit with battery-export.patch
# applied, and installs it to ~/.local/bin/librepods. The patch makes the daemon
# write $XDG_RUNTIME_DIR/librepods-battery.json, which quickshell/AirPodsBattery.qml
# reads. To bump the version: change PINNED_COMMIT, rerun, and fix the patch if it
# no longer applies. Then: systemctl --user restart librepods
set -euo pipefail

PINNED_COMMIT=672e65ad36eebf21ff1c1a508066f9197ee56d17
REPO_URL=https://github.com/kavishdevar/librepods
PATCH="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/librepods/battery-export.patch"
INSTALL_PATH="$HOME/.local/bin/librepods"

BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

git clone --quiet --filter=blob:none "$REPO_URL" "$BUILD_DIR/src"
cd "$BUILD_DIR/src"
git checkout --quiet "$PINNED_COMMIT"
git apply "$PATCH"
cd linux-rust
cargo build --release

mkdir -p "$(dirname "$INSTALL_PATH")"
install -m755 target/release/librepods "$INSTALL_PATH"
echo "Installed $INSTALL_PATH ($PINNED_COMMIT)"
