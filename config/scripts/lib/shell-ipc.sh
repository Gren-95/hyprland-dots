#!/bin/bash
# shell-ipc.sh — tell the running Quickshell about a state change.
#
# Source from another script:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/shell-ipc.sh"
#
# Usage:
#   shell_ipc <target> <function> [args...]
#
# Calls an IpcHandler function in Quickshell (`qs ipc call`). Best effort:
# silent no-op when Quickshell is not running or the target is missing, so a
# script never fails because the shell is down.

shell_ipc() {
    timeout 2 qs ipc call "$@" >/dev/null 2>&1 || true
}
