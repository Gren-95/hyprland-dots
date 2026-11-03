#!/bin/bash
# claude-activity.sh - Tell Quickshell how many Claude Code sessions are working,
# so IdleService keeps the screen from idle-locking mid-task.
#
# Called from Claude Code hooks (see docs/DAEMONS.md); the hook JSON arrives on
# stdin and carries the session id.
#
# Usage:
#   claude-activity.sh start   a session began a turn (UserPromptSubmit)
#   claude-activity.sh beat    a session is still busy (PostToolUse)
#   claude-activity.sh stop    a session finished or ended (Stop, SessionEnd)
#   claude-activity.sh prune   drop stale sessions and report the count
#
# One file per working session under $XDG_RUNTIME_DIR/claude-activity/. A session
# counts as working while its file was touched in the last STALE_MINUTES, so a
# session that dies without a Stop hook stops blocking idle on its own.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/shell-ipc.sh"

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/claude-activity"
STALE_MINUTES=15

mkdir -p "$STATE_DIR"

report_count() {
    find "$STATE_DIR" -type f -mmin +"$STALE_MINUTES" -delete 2>/dev/null
    local count
    count=$(find "$STATE_DIR" -type f | wc -l)
    shell_ipc claude active "$count"
}

action=${1:-}
if [[ "$action" == prune ]]; then
    report_count
    exit 0
fi

session=unknown
if [[ ! -t 0 ]]; then
    session=$(jq -r '.session_id // "unknown"' 2>/dev/null || echo unknown)
fi
# The id names a file, so keep it to safe characters.
session=${session//[^A-Za-z0-9_-]/_}
marker="$STATE_DIR/$session"

case "$action" in
    start)
        touch "$marker"
        report_count
        ;;
    beat)
        if [[ -e "$marker" ]]; then
            touch "$marker"
        else
            touch "$marker"
            report_count
        fi
        ;;
    stop)
        rm -f "$marker"
        report_count
        ;;
    *)
        echo "usage: $0 {start|beat|stop|prune}" >&2
        exit 2
        ;;
esac
