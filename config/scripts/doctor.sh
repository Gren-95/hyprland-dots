#!/bin/bash
# doctor.sh - Read-only health check of the dotfiles install.
#
# Checks: required commands, PyGObject, systemd user units (daemons active, none
# failed), scripts executable, symlinks managed by dots.sh, and the
# root-owned battery timer. Prints PASS/FAIL/WARN lines and a summary; exits 1
# when anything FAILed. Changes nothing.
#
# Usage: doctor.sh
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPTS_SRC="$(dirname "$SCRIPT_PATH")"
DOTS_DIR="$(dirname "$(dirname "$SCRIPTS_SRC")")"
source "$SCRIPTS_SRC/lib/deps.sh"

# User services that must be running in a graphical session.
DAEMON_UNITS=(battery-notify power-auto media-inhibit fullscreen-inhibit)
SYSTEM_BIN="/usr/local/bin/battery-charge-schedule"
SYSTEM_TIMER="battery-charge-schedule.timer"

if [[ -t 1 ]]; then
    C_PASS=$'\033[0;32m'
    C_FAIL=$'\033[0;31m'
    C_WARN=$'\033[1;33m'
    C_OFF=$'\033[0m'
else
    C_PASS=""
    C_FAIL=""
    C_WARN=""
    C_OFF=""
fi

pass_count=0
fail_count=0
warn_count=0

pass() {
    pass_count=$((pass_count + 1))
    echo "${C_PASS}PASS${C_OFF}  $1"
}
fail() {
    fail_count=$((fail_count + 1))
    echo "${C_FAIL}FAIL${C_OFF}  $1"
}
warn() {
    warn_count=$((warn_count + 1))
    echo "${C_WARN}WARN${C_OFF}  $1"
}

check_commands() {
    local dep missing=0
    for dep in "${DEPS_REQUIRED[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            fail "command missing: $dep"
            missing=1
        fi
    done
    if ((missing == 0)); then pass "all ${#DEPS_REQUIRED[@]} required commands found"; fi

    if deps_have_pygobject; then
        pass "python3 can import gi (python3-gobject)"
    else
        fail "python3 cannot import gi: install python3-gobject (media/idle inhibitors)"
    fi

    for dep in "${DEPS_OPTIONAL[@]}"; do
        command -v "$dep" >/dev/null 2>&1 || warn "optional command missing: $dep"
    done
}

check_user_units() {
    local unit state
    state=$(systemctl --user is-system-running 2>/dev/null || true)
    if [[ -z "$state" || "$state" == offline ]]; then
        fail "systemd user manager is not running"
        return 0
    fi

    for unit in "${DAEMON_UNITS[@]}"; do
        if systemctl --user is-active --quiet "$unit.service"; then
            pass "user unit active: $unit.service"
        else
            fail "user unit not active: $unit.service ($(systemctl --user is-enabled "$unit.service" 2>&1 || true))"
        fi
    done

    local failed
    failed=$(systemctl --user --failed --no-legend --plain | awk '{print $1}' || true)
    if [[ -z "$failed" ]]; then
        pass "no failed user units"
    else
        while IFS= read -r unit; do fail "user unit failed: $unit"; done <<<"$failed"
    fi
}

check_scripts_executable() {
    local f bad=0
    for f in "$SCRIPTS_SRC"/*.sh "$SCRIPTS_SRC"/lib/*.sh "$SCRIPTS_SRC/battery-charge-schedule"; do
        [[ -e "$f" ]] || continue
        if [[ ! -x "$f" ]]; then
            fail "not executable: ${f#"$DOTS_DIR"/}"
            bad=1
        fi
    done
    if ((bad == 0)); then pass "all scripts are executable"; fi
}

# Item names come from `dots.sh status` so the list has one owner.
check_symlinks() {
    local status_out item state bad=0
    status_out=$(bash "$DOTS_DIR/dots.sh" status 2>&1) || {
        fail "dots.sh status failed"
        return 0
    }
    while read -r item state _; do
        case "$state" in
            OK | MISSING | BROKEN | INCONSISTENT | DIRECTORY | FILE | UNKNOWN) ;;
            *) continue ;;
        esac
        [[ "$state" == OK ]] && continue
        # Items whose source is not in the repo (per-machine config) are skipped
        # by the manager too.
        [[ -e "$DOTS_DIR/config/$item" ]] || continue
        fail "symlink $item: $state"
        bad=1
    done <<<"$status_out"
    if ((bad == 0)); then pass "dotfiles-manager symlinks intact"; fi
}

check_system_timer() {
    if [[ ! -x "$SYSTEM_BIN" ]]; then
        warn "$SYSTEM_BIN not installed (run: dots.sh system)"
        return 0
    fi
    if cmp -s "$SYSTEM_BIN" "$SCRIPTS_SRC/battery-charge-schedule"; then
        pass "$SYSTEM_BIN matches the repo copy"
    else
        warn "$SYSTEM_BIN differs from the repo copy (re-run: dots.sh system)"
    fi
    if systemctl is-enabled --quiet "$SYSTEM_TIMER"; then
        pass "system timer enabled: $SYSTEM_TIMER"
    else
        warn "system timer not enabled: $SYSTEM_TIMER"
    fi
}

check_commands
check_user_units
check_scripts_executable
check_symlinks
check_system_timer

echo
echo "Summary: $pass_count passed, $fail_count failed, $warn_count warnings"
((fail_count == 0))
