#!/bin/bash
# disktree.sh — start Disktree on the data disk unless told otherwise.
#
# Disktree scans the home directory by default, which lives on another disk
# than /mnt/DATA, and it neither crosses filesystems nor follows symlinks, so
# ~/Documents looks empty. With no arguments scan $DATA_DIR instead; a path or
# option ("Open with" on a folder, --disk) is passed through unchanged.
#
# Usage:
#   disktree.sh [disktree arguments]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

(($#)) || set -- "$DATA_DIR"
exec "$HOME/.local/bin/disktree" "$@"
