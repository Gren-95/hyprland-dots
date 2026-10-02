#!/bin/bash
# screenshot.sh - Take a screenshot, save to file and copy to clipboard.
#
# Usage:
#   screenshot.sh                  # slurp region picker (fallback)
#   screenshot.sh "X,Y WxH"        # pre-computed region (from RegionSelector)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/screenshot.sh"

if [[ $# -ge 1 && -n "$1" ]]; then
    REGION="$1"
else
    REGION=$(slurp -d) || exit 0
fi

capture_region "$REGION"
