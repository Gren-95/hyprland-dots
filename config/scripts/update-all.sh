#!/bin/bash
# update-all.sh — snapshot, then update every package source on the system.
#
# The Timeshift snapshot is a hard gate: if it fails, nothing else runs.
# Every later step runs regardless of earlier failures; a summary at the end
# lists what failed.
#
# Usage:
#   update-all.sh
set -uo pipefail

failed=()

# Update every AppImage integrated with Gear Lever. Gear Lever re-downloads a
# file on --update even when it is current, so gate the whole step on
# --list-updates and only apply when at least one update is actually available.
update_appimages() {
    local gl=(flatpak run it.mijorus.gearlever)
    if ! command -v flatpak >/dev/null 2>&1 ||
        ! flatpak info it.mijorus.gearlever >/dev/null 2>&1; then
        echo "Gear Lever not installed, skipping."
        return 0
    fi
    if "${gl[@]}" --list-updates 2>/dev/null | grep -q "No updates available"; then
        echo "No AppImage updates available."
        return 0
    fi
    local rc=0 path
    while read -r path; do
        printf 'Updating %s\n' "$path"
        echo y | "${gl[@]}" --update "$path" || rc=1
    done < <("${gl[@]}" --list-installed 2>/dev/null | grep -oE '/home/[^[:space:]]+\.appimage')
    return "$rc"
}

_step() {
    local name=$1
    shift
    printf '\n\e[1;34m==> %s\e[0m\n' "$name"
    if ! "$@"; then
        printf '\e[1;31m!! %s failed\e[0m\n' "$name"
        failed+=("$name")
    fi
}

printf '\e[1;34m==> Timeshift snapshot\e[0m\n'
if ! sudo timeshift --create --comments "pre-update"; then
    printf '\e[1;31m!! Snapshot failed, aborting before any updates\e[0m\n'
    exit 1
fi

_step "dnf clean metadata" sudo dnf5 clean metadata
_step "dnf makecache" sudo dnf5 makecache --refresh
_step "dnf update" sudo dnf update
_step "dnf autoremove" sudo dnf autoremove
_step "flatpak update" flatpak update
_step "flatpak cleanup" flatpak remove --unused
_step "appimage updates (gear lever)" update_appimages
_step "npm globals" npm update -g
_step "uv tools" uv tool upgrade --all
_step "bun" bun upgrade
_step "fisher plugins" fish -c 'fisher update'

printf '\n\e[1;34m==> Summary\e[0m\n'
if ((${#failed[@]} == 0)); then
    echo "All steps succeeded."
else
    printf 'Failed: %s\n' "${failed[@]}"
fi

# Exit code 1 means a reboot is needed (kernel, glibc, systemd, ...).
# -C: use the metadata dnf update just fetched instead of refreshing again.
if ! dnf needs-restarting -r -C >/dev/null 2>&1; then
    printf '\e[1;33mReboot required to finish applying updates.\e[0m\n'
fi

((${#failed[@]} == 0))
