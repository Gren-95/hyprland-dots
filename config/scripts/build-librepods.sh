#!/bin/bash
# Builds LibrePods (Rust rewrite) at the pinned commit with battery-export.patch
# applied, and installs it to ~/.local/bin/librepods. The patch makes the daemon
# write $XDG_RUNTIME_DIR/librepods-battery.json, which quickshell/AirPodsBattery.qml
# reads. To bump the version: change PINNED_COMMIT, rerun, and fix the patch if it
# no longer applies. The user unit (systemd/user/librepods.service) is
# installed and enabled too, so restart.sh and the session start the daemon.
set -euo pipefail

PINNED_COMMIT=672e65ad36eebf21ff1c1a508066f9197ee56d17
REPO_URL=https://github.com/kavishdevar/librepods
PATCH="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/librepods/battery-export.patch"
INSTALL_PATH="$HOME/.local/bin/librepods"
# Copied, not symlinked: `systemctl disable` deletes a symlinked unit file,
# which would delete the repo copy (same reason as dots.sh units).
UNIT_SRC="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../systemd/user/librepods.service"
UNIT_DIR="$HOME/.config/systemd/user"

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

mkdir -p "$UNIT_DIR"
install -m644 "$UNIT_SRC" "$UNIT_DIR/librepods.service"
systemctl --user daemon-reload
systemctl --user enable librepods.service
systemctl --user restart librepods.service
echo "Installed and started librepods.service"
