#!/bin/bash
# update-all.sh — snapshot, then update every package source on the system.
#
# The Timeshift snapshot is a hard gate: if it fails, nothing else runs.
# Every later step runs regardless of earlier failures; a summary at the end
# lists what failed.
#
# Usage:
#   update-all.sh
set -uo pipefail

failed=()
skipped=()

# Exit status that marks a step as skipped because of the GitHub rate limit.
readonly RATE_LIMITED=75

# Return RATE_LIMITED, and say when the quota resets, if the unauthenticated
# GitHub API quota (60 requests/hour per IP) holds fewer than the requests a
# step needs. Querying /rate_limit is free. If the quota cannot be read, let the
# step run and report its own errors.
_github_rate_limit() {
    local needed=$1 info remaining reset
    info=$(curl -fsS --max-time 10 https://api.github.com/rate_limit 2>/dev/null) || return 0
    remaining=$(jq -r '.resources.core.remaining' <<<"$info")
    reset=$(jq -r '.resources.core.reset' <<<"$info")
    ((remaining >= needed)) && return 0
    printf '\e[1;33mGitHub API rate limit: %d left, %d needed. Resets at %s (in %d min).\e[0m\n' \
        "$remaining" "$needed" "$(date -d "@$reset" +%H:%M)" "$(((reset - $(date +%s) + 59) / 60))"
    return "$RATE_LIMITED"
}

# Update every AppImage integrated with Gear Lever. Gear Lever spends one GitHub
# API request per app on every check, and `--update --all` checks twice, so list
# the updates once as JSON and update only the apps it reports. Apps without an
# update channel cannot update; warn about them.
update_appimages() {
    local gl=(flatpak run it.mijorus.gearlever)
    local installed github_apps path updates err_file out_file rc=0 limited=0
    if ! command -v flatpak >/dev/null 2>&1 ||
        ! flatpak info it.mijorus.gearlever >/dev/null 2>&1; then
        echo "Gear Lever not installed, skipping."
        return 0
    fi

    installed=$("${gl[@]}" --list-installed 2>/dev/null)
    while read -r path; do
        printf '\e[1;33mWarning: %s has no update channel, update it manually\e[0m\n' "${path##*/}"
    done < <(grep '\[UpdatesNotAvailable\]' <<<"$installed" | grep -oE '/home/[^[:space:]]+\.appimage')

    github_apps=$(grep -c 'GithubUpdater' <<<"$installed")
    _github_rate_limit "$github_apps" || return

    err_file=$(mktemp)
    updates=$("${gl[@]}" --list-updates --json 2>"$err_file")
    if grep -q 'rate limit exceeded' "$err_file"; then
        rm -f "$err_file"
        return "$RATE_LIMITED"
    fi
    cat "$err_file" >&2
    rm -f "$err_file"

    while read -r path; do
        printf 'Updating %s\n' "${path##*/}"
        out_file=$(mktemp)
        "${gl[@]}" --update "$path" --yes 2>&1 | tee "$out_file"
        [[ ${PIPESTATUS[0]} == 0 ]] || rc=1
        if grep -q 'rate limit exceeded' "$out_file"; then
            limited=1
        fi
        rm -f "$out_file"
        ((limited)) && break
    done < <(jq -r '.updates[].path' <<<"$updates")

    ((rc != 0)) && return "$rc"
    ((limited)) && return "$RATE_LIMITED"
    return 0
}

# Upgrade bun. `bun upgrade` asks the GitHub API for the latest release and
# fails with HTTPForbidden once the quota is spent.
update_bun() {
    local out_file rc
    _github_rate_limit 1 || return
    out_file=$(mktemp)
    bun upgrade 2>&1 | tee "$out_file"
    rc=${PIPESTATUS[0]}
    grep -q HTTPForbidden "$out_file" && rc=$RATE_LIMITED
    rm -f "$out_file"
    return "$rc"
}

# Run one fisher command for one plugin. Fisher reads extra plugin names from a
# non-TTY stdin, so detach it or it swallows the caller's loop input. Fisher
# reports fetch failures on stderr but exits 0, so any stderr output counts as
# a failure.
_fisher_run() {
    local err_file rc=0
    err_file=$(mktemp)
    fish -c 'fisher $argv' "$1" "$2" 2>"$err_file" </dev/null || rc=1
    if [[ -s $err_file ]]; then
        cat "$err_file" >&2
        grep -q 'rate limit exceeded' "$err_file" && rc=$RATE_LIMITED || rc=1
    fi
    rm -f "$err_file"
    return "$rc"
}

# Print the upstream commit(s) a fisher plugin spec resolves to.
# Exit 2 for sources other than GitHub, 1 when the lookup fails.
_fisher_remote_commit() {
    local out
    [[ $1 =~ ^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)(@(.+))?$ ]] || return 2
    out=$(GIT_TERMINAL_PROMPT=0 git ls-remote "https://github.com/${BASH_REMATCH[1]}" "${BASH_REMATCH[3]:-HEAD}") || return 1
    [[ -n $out ]] || return 1
    awk '{print $1}' <<<"$out" | paste -sd,
}

# Sync fisher plugins with fish_plugins. `fisher update` re-downloads and
# reinstalls every plugin on every run and keeps no record of the installed
# commit, so remember the upstream commit per plugin and touch only plugins
# that are new, removed from fish_plugins, or whose upstream ref moved.
# A plugin with no recorded commit counts as changed.
update_fisher_plugins() {
    local plugins_file="$HOME/.config/fish/fish_plugins"
    local state_dir="$HOME/.local/state/update-all/fisher"
    local installed plugin remote lookup_rc key action rc=0 limited=0

    mkdir -p "$state_dir"
    installed=$(fish -c 'fisher list') || return 1

    while read -r plugin; do
        [[ -n $plugin ]] || continue
        grep -qixF -- "$plugin" "$plugins_file" && continue
        printf 'Removing %s (not in fish_plugins)\n' "$plugin"
        key=${plugin,,}
        _fisher_run remove "$plugin" && rm -f "$state_dir/${key//\//%}" || rc=1
    done <<<"$installed"

    while read -r plugin; do
        [[ $plugin =~ ^[^[:space:]]+$ ]] || continue
        remote=$(_fisher_remote_commit "$plugin")
        lookup_rc=$?
        case $lookup_rc in
            0) ;;
            2)
                printf '\e[1;33mWarning: %s is not a GitHub plugin, skipped\e[0m\n' "$plugin"
                continue
                ;;
            *)
                printf '\e[1;31m!! Could not check %s upstream\e[0m\n' "$plugin"
                rc=1
                continue
                ;;
        esac

        key=${plugin,,}
        key=${key//\//%}
        if ! grep -qixF -- "$plugin" <<<"$installed"; then
            action=install
        elif [[ $(cat "$state_dir/$key" 2>/dev/null) != "$remote" ]]; then
            action=update
        else
            printf '%s is up to date\n' "$plugin"
            continue
        fi

        # Fisher downloads plugins through the GitHub API, which is rate limited.
        _github_rate_limit 1 || {
            limited=1
            break
        }
        printf '%s: %s\n' "$action" "$plugin"
        _fisher_run "$action" "$plugin"
        case $? in
            0) printf '%s' "$remote" >"$state_dir/$key" ;;
            "$RATE_LIMITED")
                limited=1
                break
                ;;
            *) rc=1 ;;
        esac
    done <"$plugins_file"

    ((rc != 0)) && return "$rc"
    ((limited)) && return "$RATE_LIMITED"
    return 0
}

_step() {
    local name=$1 rc
    shift
    printf '\n\e[1;34m==> %s\e[0m\n' "$name"
    "$@"
    rc=$?
    case $rc in
        0) ;;
        "$RATE_LIMITED")
            printf '\e[1;33m-- %s skipped (GitHub rate limit)\e[0m\n' "$name"
            skipped+=("$name")
            ;;
        *)
            printf '\e[1;31m!! %s failed\e[0m\n' "$name"
            failed+=("$name")
            ;;
    esac
}

# Animate a spinner with an elapsed-seconds counter until killed. It also exits
# when the script dies, so an interrupted run cannot leave it printing.
_spinner() {
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) start=$SECONDS i=0
    while kill -0 $$ 2>/dev/null; do
        printf '\r\e[1;34m%s\e[0m %s \e[2m%ds\e[0m' "${frames[i++ % ${#frames[@]}]}" "$1" "$((SECONDS - start))"
        sleep 0.1
    done
}

# Create the pre-update snapshot behind a spinner. Timeshift's own log goes to
# a temp file and is printed only when the snapshot fails.
create_snapshot() {
    local log spinner_pid rc name start=$SECONDS
    sudo -v || return 1 # ask for the password before the spinner covers the prompt
    log=$(mktemp)

    _spinner "Creating Timeshift snapshot..." &
    spinner_pid=$!
    # The group makes the log redirect explicit: it is opened by this shell, not by sudo.
    {
        sudo timeshift --create --scripted --comments "pre-update"
    } >"$log" 2>&1 </dev/null
    rc=$?
    {
        kill "$spinner_pid"
        wait "$spinner_pid"
    } 2>/dev/null
    printf '\r\e[2K'

    if ((rc != 0)); then
        cat "$log"
        rm -f "$log"
        return "$rc"
    fi
    name=$(sed -n "s/^Tagged snapshot '\([^']*\)'.*/\1/p" "$log")
    rm -f "$log"
    printf '\e[1;32m✔\e[0m Snapshot%s created in %ds\n' "${name:+ $name}" "$((SECONDS - start))"
}

printf '\e[1;34m==> Timeshift snapshot\e[0m\n'
if ! create_snapshot; then
    printf '\e[1;31m!! Snapshot failed, aborting before any updates\e[0m\n'
    exit 1
fi

_step "dnf clean metadata" sudo dnf5 clean metadata
_step "dnf makecache" sudo dnf5 makecache --refresh
_step "dnf update" sudo dnf update
_step "dnf autoremove" sudo dnf autoremove
_step "flatpak update" flatpak update
_step "flatpak cleanup" flatpak remove --unused
_step "appimage updates (gear lever)" update_appimages
_step "npm globals" npm update -g
_step "uv tools" uv tool upgrade --all
_step "bun" update_bun
_step "fisher plugins" update_fisher_plugins

printf '\n\e[1;34m==> Summary\e[0m\n'
if ((${#failed[@]} == 0 && ${#skipped[@]} == 0)); then
    echo "All steps succeeded."
fi
if ((${#failed[@]} > 0)); then
    printf 'Failed: %s\n' "${failed[@]}"
fi
if ((${#skipped[@]} > 0)); then
    printf '\e[1;33mSkipped (GitHub rate limit, run again after the reset): %s\e[0m\n' "${skipped[@]}"
fi

# Exit code 1 means a reboot is needed (kernel, glibc, systemd, ...).
# -C: use the metadata dnf update just fetched instead of refreshing again.
if ! dnf needs-restarting -r -C >/dev/null 2>&1; then
    printf '\e[1;33mReboot required to finish applying updates.\e[0m\n'
fi

((${#failed[@]} == 0))
