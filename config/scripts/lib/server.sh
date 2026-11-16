#!/bin/bash
# server.sh — reachability check for the self-hosted servers the sync scripts
# talk to (Immich, Jellyfin), which are only reachable on the home network.
#
# Source from another script:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/server.sh"
#
# Usage:
#   server_reachable <url>
#
# Succeeds if the server answers at all, whatever the HTTP status: a 401 or 404
# still proves the host is up, and authentication problems are the caller's to
# report. Fails on connection refused, DNS failure or a timeout.

server_reachable() {
    curl -s -o /dev/null --connect-timeout 5 --max-time 10 "$1"
}
