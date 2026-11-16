#!/bin/bash
set -euo pipefail

# Toggle the games-browser docker service (web UI on http://127.0.0.1:8080/).
#
# Usage: games-browser-toggle.sh [toggle|start|stop|status]
#   status -> prints 1 (running) or 0 (stopped), nothing else

COMPOSE_FILE="$HOME/Documents/Code/games-browser/docker-compose.yml"
CONTAINER="games-browser"

is_running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ]
}

do_start() {
    # `up -d` covers both a stopped container and one that was removed.
    docker compose -f "$COMPOSE_FILE" up -d
}

do_stop() {
    docker compose -f "$COMPOSE_FILE" stop
}

case "${1:-toggle}" in
    status) is_running && echo 1 || echo 0 ;;
    start) do_start ;;
    stop) do_stop ;;
    toggle) if is_running; then do_stop; else do_start; fi ;;
    *)
        echo "usage: $(basename "$0") [toggle|start|stop|status]" >&2
        exit 2
        ;;
esac
