#!/bin/bash
# sync-toggle.sh — enable/disable/schedule background sync for immich (cron)
# and jellyfin (a Persistent systemd user timer).
#
# QuickActions calls this to toggle background sync on/off. The schedule
# lives in the user's crontab between marker comments. Toggling adds or
# removes a `#` at the start of the schedule line so cron skips it.
#
# Usage:
#   sync-toggle.sh status all                       -> "immich=0|1 jellyfin=0|1"
#   sync-toggle.sh status   <immich|jellyfin>       -> "0" or "1"
#   sync-toggle.sh toggle   <immich|jellyfin>       -> flips state, prints new state
#   sync-toggle.sh enable   <immich|jellyfin>       -> uncomment
#   sync-toggle.sh disable  <immich|jellyfin>       -> comment
#   sync-toggle.sh schedule <immich|jellyfin> <cron-expr>
#                                                   -> rewrite the 5-field cron
#                                                      schedule, preserving the
#                                                      enabled/disabled state.
#                                                      e.g. "*/30 * * * *"
set -uo pipefail

SCRIPTS="$HOME/.config/scripts"

# jellyfin runs off a Persistent systemd user timer (catches up missed runs on a
# laptop); immich stays on cron. uses_timer routes the two backends. Everything
# below (status/toggle/enable/disable/schedule) branches on it.
JELLYFIN_TIMER="jellyfin-sync.timer"
JELLYFIN_UNIT_FILE="$HOME/.config/systemd/user/jellyfin-sync.timer"
uses_timer() { [[ "$1" == "jellyfin" ]]; }

# Default cron schedule per kind (used when first installing the entry).
default_schedule_for() {
    case "$1" in
        immich)   echo "0 * * * *" ;;
        jellyfin) echo "0 4 * * *" ;;
        *) return 1 ;;
    esac
}

# Script invocation per kind (the trailing portion of the cron line).
script_invocation_for() {
    case "$1" in
        immich)   echo "bash $SCRIPTS/immich-sync.sh" ;;
        jellyfin) echo "bash $SCRIPTS/jellyfin-music-sync.sh" ;;
        *) return 1 ;;
    esac
}

# Full default cron line (schedule + invocation).
schedule_for() {
    local sched inv
    sched=$(default_schedule_for "$1") || return 1
    inv=$(script_invocation_for "$1")
    echo "$sched $inv"
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
    if uses_timer "$kind"; then
        systemctl --user is-enabled "$JELLYFIN_TIMER" >/dev/null 2>&1 && echo 1 || echo 0
        return
    fi
    ensure_installed "$kind"
    local marker line
    marker=$(marker_for "$kind")
    line=$(read_cron | awk -v m="$marker" '$0==m {found=1; next} found {print; exit}')
    [[ "$line" == \#* ]] && echo 0 || echo 1
}

# Flip the comment on the line after the marker.
flip_one() {
    local kind=$1
    if uses_timer "$kind"; then
        if systemctl --user is-enabled "$JELLYFIN_TIMER" >/dev/null 2>&1; then
            systemctl --user disable --now "$JELLYFIN_TIMER" >/dev/null 2>&1
        else
            systemctl --user enable --now "$JELLYFIN_TIMER" >/dev/null 2>&1
        fi
        return
    fi
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
    if uses_timer "$kind"; then
        if [[ "$desired" == 1 ]]; then
            systemctl --user enable --now "$JELLYFIN_TIMER" >/dev/null 2>&1
        else
            systemctl --user disable --now "$JELLYFIN_TIMER" >/dev/null 2>&1
        fi
        return
    fi
    local cur
    cur=$(status_one "$kind")
    [[ "$cur" == "$desired" ]] && return 0
    flip_one "$kind"
}

# Rewrite the cron schedule (5 fields) on the line after the marker.
# Preserves the enabled/disabled state (the leading `#` is kept or stripped
# based on the existing line). $2 is the new cron expression, e.g. "*/30 * * * *".
schedule_set() {
    local kind=$1 new_sched=$2
    if uses_timer "$kind"; then
        # For the timer $2 is a systemd OnCalendar expression (e.g. "daily" or
        # "*-*-* 04:00:00"), NOT a cron expression. Rewrite it in the unit and
        # reload. --follow-symlinks edits the repo file the symlink points to.
        if [[ -e "$JELLYFIN_UNIT_FILE" ]]; then
            sed --follow-symlinks -i "s|^OnCalendar=.*|OnCalendar=${new_sched}|" "$JELLYFIN_UNIT_FILE"
            systemctl --user daemon-reload >/dev/null 2>&1
        fi
        return
    fi
    ensure_installed "$kind"
    local marker inv cur prefix newline
    marker=$(marker_for "$kind")
    inv=$(script_invocation_for "$kind")
    cur=$(status_one "$kind")
    prefix=""
    [[ "$cur" == "0" ]] && prefix="#"
    newline="${prefix}${new_sched} ${inv}"
    read_cron | awk -v m="$marker" -v newline="$newline" '
        rep { print newline; rep = 0; next }
        $0 == m { rep = 1 }
        { print }
    ' | crontab - >/dev/null 2>&1
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
    schedule)
        sched=${3:-}
        case "$arg" in
            immich|jellyfin)
                [[ -z "$sched" ]] && { echo "usage: $0 schedule {immich|jellyfin} '<cron-expr>'" >&2; exit 2; }
                schedule_set "$arg" "$sched"
                ;;
            *) echo "usage: $0 schedule {immich|jellyfin} '<cron-expr>'" >&2; exit 2 ;;
        esac
        ;;
    *)
        echo "usage: $0 {status|toggle|enable|disable|schedule} {all|immich|jellyfin} [args]" >&2
        exit 2
        ;;
esac
