#!/bin/bash
set -euo pipefail

# Toggle the Windows VM that backs WinApps (dockur/windows container).
#
# Stopping the container is what actually frees the VM's 6 GB of RAM.
# WinApps' own AUTOPAUSE issues `docker pause`, which only freezes the
# container's CPU — the guest's memory stays resident. So this toggle is
# the only thing that gives the RAM back.
#
# Usage: winvm-toggle.sh [toggle|start|stop|status] [--force]
#   status -> prints 1 (running) or 0 (stopped), nothing else

COMPOSE_FILE="$HOME/winapps/compose.yaml"
CONTAINER="WinApps"

is_running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ]
}

# RemoteApp sessions hold unsaved Office documents. Windows gets a graceful
# ACPI shutdown, but a "Save changes?" dialog inside the guest has no visible
# window once the RemoteApp client dies — it would just block until the grace
# period expires and the VM is killed, losing the document. So refuse by
# default and let the user close their apps.
open_sessions() {
    # Anchor to the binary name: a bare "xfreerdp" pattern also matches any
    # shell whose command line merely mentions it (including this script's
    # own caller), which would parse garbage back out.
    pgrep -af '^[^ ]*freerdp ' 2>/dev/null |
        grep -F 'app:program' |
        sed -n 's/.*name:\(.*\) \/v:.*/\1/p' | sort -u | paste -sd', ' || true
}

do_stop() {
    local force="${1:-}"
    local open
    open="$(open_sessions)"
    if [ -n "$open" ] && [ "$force" != "--force" ]; then
        notify-send -u critical -a "Windows VM" \
            "Windows VM still in use" \
            "Close these first so nothing is lost: ${open}" 2>/dev/null || true
        exit 1
    fi
    docker compose -f "$COMPOSE_FILE" stop
}

do_start() {
    # `up -d` covers both a stopped container and one that was removed.
    docker compose -f "$COMPOSE_FILE" up -d
}

case "${1:-toggle}" in
    status) is_running && echo 1 || echo 0 ;;
    start)  do_start ;;
    stop)   do_stop "${2:-}" ;;
    toggle) if is_running; then do_stop "${2:-}"; else do_start; fi ;;
    *)      echo "usage: $(basename "$0") [toggle|start|stop|status] [--force]" >&2; exit 2 ;;
esac
