#!/bin/bash
# sync-toggle.sh — enable/disable cron entries for immich/jellyfin sync.
#
# QuickActions calls this to toggle background sync on/off. The schedule
# lives in the user's crontab between marker comments. Toggling adds or
# removes a `#` at the start of the schedule line so cron skips it.
#
# Usage:
#   sync-toggle.sh status all                -> "immich=0|1 jellyfin=0|1"
#   sync-toggle.sh status <immich|jellyfin>  -> "0" or "1"
#   sync-toggle.sh toggle <immich|jellyfin>  -> flips state, no output
#   sync-toggle.sh enable <immich|jellyfin>  -> uncomment
#   sync-toggle.sh disable <immich|jellyfin> -> comment
set -uo pipefail

SCRIPTS="$HOME/.config/scripts"

# Map sync kind → cron schedule + script invocation.
schedule_for() {
    case "$1" in
        immich)   echo "0 * * * * bash $SCRIPTS/immich-sync.sh" ;;
        jellyfin) echo "0 */2 * * * bash $SCRIPTS/jellyfin-music-sync.sh" ;;
        *) return 1 ;;
    esac
}

marker_for() { echo "# QSSYNC:$1"; }

# Read the current crontab (empty string if user has none).
read_cron() { crontab -l 2>/dev/null || true; }

# Ensure the marker + schedule line exist (added in disabled state on first run).
ensure_installed() {
    local kind=$1
    local marker schedule cur
    marker=$(marker_for "$kind")
    schedule=$(schedule_for "$kind") || return 1
    cur=$(read_cron)
    if ! grep -qxF "$marker" <<<"$cur"; then
        {
            [[ -n "$cur" ]] && printf '%s\n' "$cur"
            printf '%s\n' "$marker"
            printf '#%s\n' "$schedule"
        } | crontab - >/dev/null 2>&1
    fi
}

# Status: 1 if the line after the marker is enabled (no leading #), else 0.
status_one() {
    local kind=$1
    ensure_installed "$kind"
    local marker line
    marker=$(marker_for "$kind")
    line=$(read_cron | awk -v m="$marker" '$0==m {found=1; next} found {print; exit}')
    [[ "$line" == \#* ]] && echo 0 || echo 1
}

# Flip the comment on the line after the marker.
flip_one() {
    local kind=$1
    ensure_installed "$kind"
    local marker
    marker=$(marker_for "$kind")
    read_cron | awk -v m="$marker" '
        flip {
            if (substr($0,1,1) == "#") sub(/^#/, "")
            else $0 = "#" $0
            flip = 0
        }
        $0 == m { flip = 1 }
        { print }
    ' | crontab - >/dev/null 2>&1
}

set_one() {
    local kind=$1 desired=$2
    local cur
    cur=$(status_one "$kind")
    [[ "$cur" == "$desired" ]] && return 0
    flip_one "$kind"
}

cmd=${1:-}
arg=${2:-}

case "$cmd" in
    status)
        case "$arg" in
            all)              echo "immich=$(status_one immich) jellyfin=$(status_one jellyfin)" ;;
            immich|jellyfin)  status_one "$arg" ;;
            *)                echo "usage: $0 status {all|immich|jellyfin}" >&2; exit 2 ;;
        esac
        ;;
    toggle)
        case "$arg" in
            immich|jellyfin)
                flip_one "$arg"
                # Print the new state so callers can react in one call.
                status_one "$arg"
                ;;
            *) echo "usage: $0 toggle {immich|jellyfin}" >&2; exit 2 ;;
        esac
        ;;
    enable)
        case "$arg" in
            immich|jellyfin) set_one "$arg" 1 ;;
            *) echo "usage: $0 enable {immich|jellyfin}" >&2; exit 2 ;;
        esac
        ;;
    disable)
        case "$arg" in
            immich|jellyfin) set_one "$arg" 0 ;;
            *) echo "usage: $0 disable {immich|jellyfin}" >&2; exit 2 ;;
        esac
        ;;
    *)
        echo "usage: $0 {status|toggle|enable|disable} {all|immich|jellyfin}" >&2
        exit 2
        ;;
esac
