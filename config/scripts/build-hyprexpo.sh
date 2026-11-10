#!/bin/bash
# build-hyprexpo.sh — rebuild the local hyprexpo plugin against the installed
# Hyprland headers and install it where hl.plugin.load() expects it.
#
# Hyprland only loads a plugin that embeds its own commit hash, so every
# Hyprland update breaks the plugin until it is rebuilt. This script compares
# the hash in the installed headers with the one in the installed plugin and
# rebuilds only on a mismatch. `make` does not track system headers, so the
# build is forced with -B.
#
# The plugin is replaced with an atomic rename. A running Hyprland maps the old
# file; overwriting it in place would crash the compositor. The new build
# loads at the next Hyprland start.
#
# Build output goes to ~/.cache/hyprexpo-build.log. Status lines go to stderr,
# so the dnf actions plugin (which parses stdout) never sees them.
#
# Usage:
#   build-hyprexpo.sh                 Rebuild if the installed plugin is stale
#   build-hyprexpo.sh --install-hook  Install a dnf5 action (sudo) that runs this
#                                     script after every hyprland-devel update
set -euo pipefail

SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
source "$(dirname "$SCRIPT_PATH")/lib/notify.sh"

SRC_DIR="$HOME/.local/src/hyprexpo"
PLUGIN_PATH="$HOME/.local/lib/hyprland/plugins/hyprexpo.so"
VERSION_HEADER=/usr/include/hyprland/src/version.h
BUILD_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/hyprexpo-build.log"
ACTIONS_FILE=/etc/dnf/libdnf5-plugins/actions.d/hyprexpo.actions

# notify-send fails without a graphical session; that must not fail the build.
notify_user() {
    notify "$@" || true
}

fail() {
    echo "hyprexpo: $1" >&2
    notify_user critical hyprexpo-build dialog-error "hyprexpo rebuild failed" "$1"
    exit 1
}

install_hook() {
    local user uid
    user=$(id -un)
    uid=$(id -u)
    # The actions plugin runs as root. runuser drops back to this user so the
    # build writes to this user's ~/.local; XDG_RUNTIME_DIR lets notify-send
    # find the user's session bus. The fields are colon-separated, so the
    # command must not contain a colon.
    local action="post_transaction:hyprland-devel:in::/usr/sbin/runuser -u $user -- /usr/bin/env HOME=$HOME XDG_RUNTIME_DIR=/run/user/$uid $SCRIPT_PATH"

    echo "Installing $ACTIONS_FILE (needs sudo)..." >&2
    printf '# Rebuild the hyprexpo plugin when Hyprland headers change.\n%s\n' "$action" |
        sudo install -Dm644 /dev/stdin "$ACTIONS_FILE"
    echo "Installed. It runs after the next dnf transaction that touches hyprland-devel." >&2
}

installed_hyprland_hash() {
    sed -n 's/^#define GIT_COMMIT_HASH[[:space:]]*"\([0-9a-f]*\)"$/\1/p' "$VERSION_HEADER"
}

if [[ "${1:-}" == "--install-hook" ]]; then
    install_hook
    exit 0
fi

[[ -r "$VERSION_HEADER" ]] || fail "Hyprland headers not found at $VERSION_HEADER (install hyprland-devel)"
[[ -d "$SRC_DIR" ]] || fail "Plugin source not found at $SRC_DIR"

hash=$(installed_hyprland_hash)
[[ -n "$hash" ]] || fail "Could not read the Hyprland commit hash from $VERSION_HEADER"

if [[ -f "$PLUGIN_PATH" ]] && grep -qaF "$hash" "$PLUGIN_PATH"; then
    echo "hyprexpo: already built for Hyprland ${hash:0:8}, nothing to do." >&2
    exit 0
fi

echo "hyprexpo: rebuilding for Hyprland ${hash:0:8} (log: $BUILD_LOG)..." >&2
mkdir -p "$(dirname "$BUILD_LOG")" "$(dirname "$PLUGIN_PATH")"
if ! (cd "$SRC_DIR" && make -B all) >"$BUILD_LOG" 2>&1; then
    fail "Build failed. See $BUILD_LOG"
fi
grep -qaF "$hash" "$SRC_DIR/hyprexpo.so" || fail "Built plugin does not embed Hyprland ${hash:0:8}. See $BUILD_LOG"

tmp=$(mktemp "$PLUGIN_PATH.XXXXXX")
trap 'rm -f "$tmp"' EXIT
strip --strip-debug -o "$tmp" "$SRC_DIR/hyprexpo.so"
chmod 755 "$tmp"
mv -f "$tmp" "$PLUGIN_PATH"

echo "hyprexpo: installed $PLUGIN_PATH (Hyprland ${hash:0:8}). Log out and back in to load it." >&2
notify_user normal hyprexpo-build dialog-information "hyprexpo rebuilt" "Built for Hyprland ${hash:0:8}. Log out and back in to load it."
