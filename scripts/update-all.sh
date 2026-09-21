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

_step() {
    local name=$1; shift
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

_step "dnf update"          sudo dnf update
_step "dnf autoremove"      sudo dnf autoremove
_step "flatpak update"      flatpak update
_step "flatpak cleanup"     flatpak remove --unused
_step "npm globals"         npm update -g
_step "uv tools"            uv tool upgrade --all
_step "bun"                 bun upgrade
_step "fisher plugins"      fish -c 'fisher update'

printf '\n\e[1;34m==> Summary\e[0m\n'
if (( ${#failed[@]} == 0 )); then
    echo "All steps succeeded."
else
    printf 'Failed: %s\n' "${failed[@]}"
fi

# Exit code 1 means a reboot is needed (kernel, glibc, systemd, ...).
# -C: use the metadata dnf update just fetched instead of refreshing again.
if ! dnf needs-restarting -r -C >/dev/null 2>&1; then
    printf '\e[1;33mReboot required to finish applying updates.\e[0m\n'
fi

(( ${#failed[@]} == 0 ))
