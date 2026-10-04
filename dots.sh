#!/bin/bash
# dots.sh - Install, set up and manage the hyprland-dots dotfiles.
#
# Usage: dots.sh <command> [options]
#
# One-command install on a fresh machine:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Gren-95/hyprland-dots/main/dots.sh) install
#
# Run `dots.sh --help` for the command list.

# Constants
DOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Every CONFIG_ITEMS entry lives under config/, mirroring ~/.config.
CONFIG_SRC_DIR="$DOTS_DIR/config"
CONFIG_DIR="$HOME/.config"
LOG_FILE="$CONFIG_DIR/.dotfiles_symlink.log"
LOCK_FILE="/tmp/dots.lock"

# Config items to manage
CONFIG_ITEMS=(
    "hypr"
    "kitty"
    "quickshell"
    "swappy"
    "scripts"
    "wayvnc"
    "fish"
    "ranger"
    "btop"
    "gtk-3.0"
    "gtk-4.0"
    "kdeglobals"
    "immich"
    "jellyfin"
)

# Options
# System-level files. Unlike everything in CONFIG_ITEMS these are COPIED, not
# symlinked: systemd runs them as root, and root must not execute files that
# live in a user-writable repo. Re-run "system" after editing them here.
SYSTEM_SCRIPTS=(
    "config/scripts/battery-charge-schedule"
)
SYSTEM_UNITS=(
    "systemd/system/battery-charge-schedule.service"
    "systemd/system/battery-charge-schedule.timer"
)
SYSTEM_TIMERS=(
    "battery-charge-schedule.timer"
)
# Session daemons run as systemd user units. Also COPIED, not symlinked:
# `systemctl disable` deletes a symlinked unit file, which would delete the repo
# copy. Enabled (not started): they start with the next graphical session, and
# restart.sh (Super+B) restarts them.
USER_UNITS=(
    "systemd/user/battery-notify.service"
    "systemd/user/power-auto.service"
    "systemd/user/media-inhibit.service"
    "systemd/user/fullscreen-inhibit.service"
)
USER_UNIT_DIR="$HOME/.config/systemd/user"
SYSTEM_BIN_DIR="/usr/local/bin"
SYSTEM_UNIT_DIR="/etc/systemd/system"

DRY_RUN=false
FORCE=false
VERBOSE=false
ASSUME_YES=false

# Colors (if terminal supports it)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

################################################################################
# Utility Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1"
    fi
}

# Create lock file to prevent concurrent execution
acquire_lock() {
    if [[ -e "$LOCK_FILE" ]]; then
        log_error "Another instance is running (lock file exists: $LOCK_FILE)"
        exit 1
    fi
    echo $$ >"$LOCK_FILE"
    verbose "Lock file created: $LOCK_FILE"
}

# Remove lock file
release_lock() {
    rm -f "$LOCK_FILE"
    verbose "Lock file removed: $LOCK_FILE"
}

# Cleanup on exit
cleanup() {
    release_lock
}

# Trap signals for cleanup
trap cleanup EXIT INT TERM

# Check if required tools are available
check_manager_tools() {
    local missing=()

    command -v jq >/dev/null 2>&1 || missing+=("jq")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        log_error "Please install them and try again"
        exit 1
    fi
}

# Verify dots directory exists
verify_dots_dir() {
    if [[ ! -d "$DOTS_DIR" ]]; then
        log_error "Dots directory not found: $DOTS_DIR"
        exit 1
    fi
}

# Check disk space (requires at least 100MB free)
check_disk_space() {
    local available
    available=$(df -BM "$CONFIG_DIR" | awk 'NR==2 {print $4}' | sed 's/M//')
    if [[ $available -lt 100 ]]; then
        log_error "Insufficient disk space. Available: ${available}MB, Required: 100MB"
        exit 1
    fi
    verbose "Disk space check: ${available}MB available"
}

# Get timestamp for backups
get_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

# Get canonical path (resolve symlinks and relative paths)
get_canonical_path() {
    readlink -f "$1"
}

# Confirm action with user
confirm() {
    if [[ "$FORCE" == true ]]; then
        return 0
    fi

    echo -n "$1 [y/N]: "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

################################################################################
# Log Management
################################################################################

# Initialize log file
init_log() {
    local timestamp
    timestamp=$(get_timestamp)
    cat >"$LOG_FILE" <<EOF
{
  "version": "1.0",
  "operations": [],
  "last_backup": "$timestamp"
}
EOF
    verbose "Log file initialized: $LOG_FILE"
}

# Add operation to log
log_operation() {
    local item="$1"
    local action="$2"
    local backup_path="$3"
    local timestamp
    timestamp=$(get_timestamp)

    if [[ "$DRY_RUN" == true ]]; then
        return
    fi

    # Create log if it doesn't exist
    if [[ ! -f "$LOG_FILE" ]]; then
        init_log
    fi

    # Add operation to log
    local temp_log
    temp_log=$(mktemp)
    jq --arg item "$item" \
        --arg action "$action" \
        --arg backup "$backup_path" \
        --arg time "$timestamp" \
        '.operations += [{
           "item": $item,
           "action": $action,
           "backup_path": $backup,
           "timestamp": $time
       }] | .last_backup = $time' "$LOG_FILE" >"$temp_log"

    mv "$temp_log" "$LOG_FILE"
    verbose "Logged operation: $action $item"
}

################################################################################
# Core Operations
################################################################################

# Check symlink status
check_symlink() {
    local item="$1"
    local target="$CONFIG_DIR/$item"
    local source="$CONFIG_SRC_DIR/$item"
    local canonical_source
    canonical_source=$(get_canonical_path "$source")

    if [[ ! -e "$target" && ! -L "$target" ]]; then
        echo "MISSING"
    elif [[ -L "$target" ]]; then
        local link_target
        link_target=$(readlink "$target")
        local canonical_link
        canonical_link=$(get_canonical_path "$target")

        if [[ ! -e "$target" ]]; then
            echo "BROKEN"
        elif [[ "$canonical_link" == "$canonical_source" ]]; then
            echo "OK"
        else
            echo "INCONSISTENT"
        fi
    elif [[ -d "$target" ]]; then
        echo "DIRECTORY"
    elif [[ -f "$target" ]]; then
        echo "FILE"
    else
        echo "UNKNOWN"
    fi
}

# Backup a directory
backup_directory() {
    local item="$1"
    local target="$CONFIG_DIR/$item"
    local timestamp
    timestamp=$(get_timestamp)
    local backup_name="${item}_bak_${timestamp}"
    local backup_path="$CONFIG_DIR/$backup_name"

    # Check if backup name already exists (shouldn't happen with timestamps)
    local counter=1
    while [[ -e "$backup_path" ]]; do
        backup_name="${item}_bak_${timestamp}_${counter}"
        backup_path="$CONFIG_DIR/$backup_name"
        ((counter++))
    done

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would backup: $target -> $backup_path"
        echo "$backup_path"
        return 0
    fi

    verbose "Backing up: $target -> $backup_path"
    mv "$target" "$backup_path" || {
        log_error "Failed to backup $target"
        return 1
    }

    log_success "Backed up: $item -> $backup_name"
    echo "$backup_path"
}

# Create symlink
create_symlink() {
    local item="$1"
    local source="$CONFIG_SRC_DIR/$item"
    local target="$CONFIG_DIR/$item"

    if [[ ! -e "$source" ]]; then
        log_error "Source does not exist: $source"
        return 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create symlink: $target -> $source"
        return 0
    fi

    verbose "Creating symlink: $target -> $source"
    ln -sf "$source" "$target" || {
        log_error "Failed to create symlink for $item"
        return 1
    }

    # Verify symlink
    local canonical_target
    canonical_target=$(get_canonical_path "$target")
    local canonical_source
    canonical_source=$(get_canonical_path "$source")

    if [[ "$canonical_target" != "$canonical_source" ]]; then
        log_error "Symlink verification failed for $item"
        return 1
    fi

    log_success "Symlinked: $item"
    return 0
}

# Remove symlink
remove_symlink() {
    local item="$1"
    local target="$CONFIG_DIR/$item"

    if [[ ! -L "$target" ]]; then
        verbose "Not a symlink, skipping: $target"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would remove symlink: $target"
        return 0
    fi

    verbose "Removing symlink: $target"
    rm "$target" || {
        log_error "Failed to remove symlink: $target"
        return 1
    }

    return 0
}

# Restore from backup
restore_backup() {
    local backup_path="$1"
    local item="$2"
    local target="$CONFIG_DIR/$item"

    if [[ ! -e "$backup_path" ]]; then
        log_warning "Backup not found: $backup_path"
        return 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would restore: $backup_path -> $target"
        return 0
    fi

    verbose "Restoring: $backup_path -> $target"
    mv "$backup_path" "$target" || {
        log_error "Failed to restore $backup_path"
        return 1
    }

    log_success "Restored: $item"
    return 0
}

################################################################################
# Commands
################################################################################

cmd_backup() {
    log_info "Starting backup and symlink operation..."

    # Pre-flight checks
    verify_dots_dir
    check_disk_space

    local symlinked=0
    local backed_up=0
    local skipped=0
    local failed=0

    for item in "${CONFIG_ITEMS[@]}"; do
        local source="$CONFIG_SRC_DIR/$item"
        local target="$CONFIG_DIR/$item"
        local status
        status=$(check_symlink "$item")

        verbose "Processing: $item (status: $status)"

        # Check if source exists
        if [[ ! -e "$source" ]]; then
            log_warning "Source not found, skipping: $source"
            ((skipped++))
            continue
        fi

        case "$status" in
            OK)
                log_info "Already correct: $item"
                ((skipped++))
                ;;

            INCONSISTENT | BROKEN)
                log_info "Fixing symlink: $item"
                remove_symlink "$item" || {
                    ((failed++))
                    continue
                }
                if create_symlink "$item"; then
                    log_operation "$item" "fixed" ""
                    ((symlinked++))
                else
                    ((failed++))
                fi
                ;;

            DIRECTORY)
                log_info "Backing up directory: $item"
                backup_path=$(backup_directory "$item")
                if [[ $? -eq 0 ]]; then
                    if create_symlink "$item"; then
                        log_operation "$item" "backup_and_symlink" "$backup_path"
                        ((backed_up++))
                        ((symlinked++))
                    else
                        # Rollback: restore backup
                        if [[ "$DRY_RUN" == false ]]; then
                            log_warning "Symlink failed, rolling back..."
                            mv "$backup_path" "$target"
                        fi
                        ((failed++))
                    fi
                else
                    ((failed++))
                fi
                ;;

            FILE)
                log_error "Target is a file (manual intervention required): $target"
                ((failed++))
                ;;

            MISSING)
                log_info "Creating symlink: $item"
                if create_symlink "$item"; then
                    log_operation "$item" "symlink" ""
                    ((symlinked++))
                else
                    ((failed++))
                fi
                ;;

            *)
                log_error "Unknown status for $item: $status"
                ((failed++))
                ;;
        esac
    done

    # Summary
    echo ""
    log_info "========== SUMMARY =========="
    echo "  Symlinked: $symlinked"
    echo "  Backed up: $backed_up"
    echo "  Skipped:   $skipped"
    echo "  Failed:    $failed"

    if [[ "$DRY_RUN" == false && -f "$LOG_FILE" ]]; then
        echo "  Log file:  $LOG_FILE"
    fi

    if [[ $failed -gt 0 ]]; then
        log_error "Some operations failed. Please review the errors above."
        exit 1
    fi

    log_success "Backup and symlink operation completed!"
}

cmd_undo() {
    log_info "Starting undo operation..."

    # Check if log file exists
    if [[ ! -f "$LOG_FILE" ]]; then
        log_error "No log file found. Nothing to undo."
        exit 1
    fi

    # Validate log file
    if ! jq empty "$LOG_FILE" 2>/dev/null; then
        log_error "Log file is corrupted or invalid JSON"
        exit 1
    fi

    # Get operations from log
    local operations
    operations=$(jq -r '.operations | length' "$LOG_FILE")

    if [[ $operations -eq 0 ]]; then
        log_info "No operations to undo."
        exit 0
    fi

    # Display what will be undone
    log_info "Found $operations operation(s) to undo:"
    jq -r '.operations[] | "  - \(.action) \(.item)"' "$LOG_FILE"
    echo ""

    if ! confirm "Proceed with undo?"; then
        log_info "Undo cancelled."
        exit 0
    fi

    local restored=0
    local removed=0
    local failed=0

    # Process operations in reverse order
    while IFS= read -r op; do
        local item
        item=$(echo "$op" | jq -r '.item')
        local action
        action=$(echo "$op" | jq -r '.action')
        local backup_path
        backup_path=$(echo "$op" | jq -r '.backup_path')

        verbose "Undoing: $action $item"

        # Remove symlink if it exists
        if remove_symlink "$item"; then
            ((removed++))
        else
            ((failed++))
            continue
        fi

        # Restore backup if it exists
        if [[ -n "$backup_path" && "$backup_path" != "null" ]]; then
            if restore_backup "$backup_path" "$item"; then
                ((restored++))
            else
                ((failed++))
            fi
        fi
    done < <(jq -c '.operations | reverse | .[]' "$LOG_FILE")

    # Archive log file
    if [[ "$DRY_RUN" == false ]]; then
        local archive
        archive="${LOG_FILE}.$(get_timestamp)"
        mv "$LOG_FILE" "$archive"
        log_info "Log archived: $archive"
    fi

    # Summary
    echo ""
    log_info "========== SUMMARY =========="
    echo "  Symlinks removed: $removed"
    echo "  Backups restored: $restored"
    echo "  Failed:           $failed"

    if [[ $failed -gt 0 ]]; then
        log_error "Some operations failed. Please review the errors above."
        exit 1
    fi

    log_success "Undo operation completed!"
}

cmd_status() {
    log_info "Checking symlink status..."
    echo ""

    printf "%-15s %-15s %-50s\n" "ITEM" "STATUS" "DETAILS"
    printf "%-15s %-15s %-50s\n" "----" "------" "-------"

    local ok=0
    local issues=0

    for item in "${CONFIG_ITEMS[@]}"; do
        local status
        status=$(check_symlink "$item")
        local target="$CONFIG_DIR/$item"
        local details=""

        case "$status" in
            OK)
                details="${GREEN}Symlink OK${NC}"
                ((ok++))
                ;;
            INCONSISTENT)
                local link_target
                link_target=$(readlink "$target")
                details="${YELLOW}Points to: $link_target${NC}"
                ((issues++))
                ;;
            BROKEN)
                local link_target
                link_target=$(readlink "$target")
                details="${RED}Broken link to: $link_target${NC}"
                ((issues++))
                ;;
            MISSING)
                details="${YELLOW}Not found${NC}"
                ((issues++))
                ;;
            DIRECTORY)
                details="${YELLOW}Regular directory (not symlinked)${NC}"
                ((issues++))
                ;;
            FILE)
                details="${RED}Regular file (not symlinked)${NC}"
                ((issues++))
                ;;
            *)
                details="${RED}Unknown${NC}"
                ((issues++))
                ;;
        esac

        printf "%-15s %-15s %-50b\n" "$item" "$status" "$details"
    done

    echo ""
    log_info "========== SUMMARY =========="
    echo "  OK:     $ok"
    echo "  Issues: $issues"

    if [[ $issues -gt 0 ]]; then
        echo ""
        log_info "Suggestions:"
        echo "  - Run 'dots.sh fix' to fix inconsistent symlinks"
        echo "  - Run 'dots.sh backup' to create missing symlinks"
    fi
}

cmd_fix() {
    log_info "Fixing inconsistent symlinks..."

    verify_dots_dir

    local fixed=0
    local failed=0
    local skipped=0

    for item in "${CONFIG_ITEMS[@]}"; do
        local status
        status=$(check_symlink "$item")

        if [[ "$status" == "INCONSISTENT" || "$status" == "BROKEN" ]]; then
            log_info "Fixing: $item"

            if remove_symlink "$item" && create_symlink "$item"; then
                log_operation "$item" "fixed" ""
                ((fixed++))
            else
                ((failed++))
            fi
        else
            verbose "Skipping: $item (status: $status)"
            ((skipped++))
        fi
    done

    # Summary
    echo ""
    log_info "========== SUMMARY =========="
    echo "  Fixed:   $fixed"
    echo "  Skipped: $skipped"
    echo "  Failed:  $failed"

    if [[ $failed -gt 0 ]]; then
        log_error "Some operations failed. Please review the errors above."
        exit 1
    fi

    if [[ $fixed -eq 0 ]]; then
        log_success "No symlinks needed fixing!"
    else
        log_success "Fix operation completed!"
    fi
}

# Remove dangling ~/.config symlinks that point into the dots repo.
# Links become dangling when an item is dropped from CONFIG_ITEMS and its
# directory is deleted from the repo. Unrelated broken links are left alone.
cmd_prune() {
    local dots_physical
    dots_physical="$(readlink -f "$DOTS_DIR")"
    local removed=0 kept=0

    for link in "$CONFIG_DIR"/* "$CONFIG_DIR"/.*; do
        [[ -L "$link" ]] || continue
        [[ -e "$link" ]] && continue

        local target
        target="$(readlink "$link")"
        if [[ "$target" != "$DOTS_DIR"/* && "$target" != "$dots_physical"/* ]]; then
            verbose "Dangling but not ours, keeping: $link -> $target"
            kept=$((kept + 1))
            continue
        fi

        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would remove dangling symlink: $link -> $target"
            removed=$((removed + 1))
            continue
        fi

        log_info "Removing dangling symlink: $link -> $target"
        rm "$link" || {
            log_error "Failed to remove: $link"
            continue
        }
        removed=$((removed + 1))
    done

    if [[ $removed -eq 0 ]]; then
        log_success "No dangling symlinks found!"
    else
        log_success "Prune completed: $removed dangling link(s) handled, $kept unrelated kept."
    fi
}

# Install root-owned scripts and systemd system units, then enable their timers.
cmd_system() {
    verify_dots_dir

    if ! command -v sudo &>/dev/null; then
        log_error "sudo is required to install system files"
        return 1
    fi

    log_info "Installing system files (requires sudo)"

    if [[ "$DRY_RUN" != true ]] && [[ "$FORCE" != true ]]; then
        confirm "Install ${#SYSTEM_SCRIPTS[@]} script(s) to $SYSTEM_BIN_DIR and ${#SYSTEM_UNITS[@]} unit(s) to $SYSTEM_UNIT_DIR?" || {
            log_info "Aborted"
            return 0
        }
    fi

    local item source
    for item in "${SYSTEM_SCRIPTS[@]}"; do
        source="$DOTS_DIR/$item"
        if [[ ! -f "$source" ]]; then
            log_error "Missing: $source"
            return 1
        fi
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would install $item -> $SYSTEM_BIN_DIR/$(basename "$item") (755 root:root)"
            continue
        fi
        sudo install -m 755 -o root -g root "$source" "$SYSTEM_BIN_DIR/" || {
            log_error "Failed to install $item"
            return 1
        }
        log_success "Installed: $SYSTEM_BIN_DIR/$(basename "$item")"
    done

    for item in "${SYSTEM_UNITS[@]}"; do
        source="$DOTS_DIR/$item"
        if [[ ! -f "$source" ]]; then
            log_error "Missing: $source"
            return 1
        fi
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would install $item -> $SYSTEM_UNIT_DIR/$(basename "$item") (644 root:root)"
            continue
        fi
        sudo install -m 644 -o root -g root "$source" "$SYSTEM_UNIT_DIR/" || {
            log_error "Failed to install $item"
            return 1
        }
        log_success "Installed: $SYSTEM_UNIT_DIR/$(basename "$item")"
    done

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would run: systemctl daemon-reload"
        local timer
        for timer in "${SYSTEM_TIMERS[@]}"; do
            log_info "[DRY RUN] Would enable --now $timer"
        done
        return 0
    fi

    sudo systemctl daemon-reload || {
        log_error "systemctl daemon-reload failed"
        return 1
    }

    local timer
    for timer in "${SYSTEM_TIMERS[@]}"; do
        sudo systemctl enable --now "$timer" || {
            log_error "Failed to enable $timer"
            return 1
        }
        log_success "Enabled: $timer"
    done

    return 0
}

# Install the session daemon units into ~/.config/systemd/user and enable them.
# Nothing is started here.
cmd_units() {
    verify_dots_dir

    local item source unit
    for item in "${USER_UNITS[@]}"; do
        source="$DOTS_DIR/$item"
        unit="$(basename "$item")"
        if [[ ! -f "$source" ]]; then
            log_error "Missing: $source"
            return 1
        fi
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would install $item -> $USER_UNIT_DIR/$unit and enable it"
            continue
        fi
        mkdir -p "$USER_UNIT_DIR"
        install -m 644 "$source" "$USER_UNIT_DIR/$unit" || {
            log_error "Failed to install $item"
            return 1
        }
        log_success "Installed: $USER_UNIT_DIR/$unit"
    done

    [[ "$DRY_RUN" == true ]] && return 0

    systemctl --user daemon-reload || {
        log_error "systemctl --user daemon-reload failed"
        return 1
    }
    for item in "${USER_UNITS[@]}"; do
        unit="$(basename "$item")"
        systemctl --user enable "$unit" >/dev/null 2>&1 || {
            log_error "Failed to enable $unit"
            return 1
        }
        log_success "Enabled: $unit"
    done
    return 0
}

################################################################################
# Setup (dependencies, symlinks, units, one-time system configuration)
################################################################################

# Check if running on Fedora/Nobara
check_distro() {
    if [[ -f /etc/fedora-release ]] || [[ -f /etc/nobara-release ]]; then
        return 0
    else
        log_warning "This script is optimized for Fedora/Nobara"
        return 1
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ask <prompt> <Y|N>: yes/no question; <Y|N> is the default answer (Enter).
# Returns 0 for yes. With --yes every question is answered yes.
ask() {
    local prompt=$1 default=$2 reply=""
    if [[ "$ASSUME_YES" == true ]]; then
        echo "$prompt yes (--yes)"
        return 0
    fi
    read -p "$prompt " -n 1 -r reply || true
    echo
    if [[ "$default" == "Y" ]]; then
        [[ ! $reply =~ ^[Nn]$ ]]
    else
        [[ $reply =~ ^[Yy]$ ]]
    fi
}

# Check dependencies
check_setup_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()
    mapfile -t missing_deps < <(deps_missing_required)
    if ! deps_have_pygobject; then
        missing_deps+=("python3-gobject")
    fi

    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        log_success "All dependencies are installed"
        return 0
    else
        log_warning "Missing dependencies: ${missing_deps[*]}"
        return 1
    fi
}

# Install dependencies (Fedora/Nobara)
install_dependencies() {
    if ! check_distro; then
        log_error "Automatic installation only supported on Fedora/Nobara"
        return 1
    fi

    log_info "Adding required COPR repositories..."
    sudo dnf copr enable -y lionheartp/Hyprland
    sudo dnf copr enable -y errornointernet/quickshell ||
        log_warning "Quickshell COPR not available — build from source: https://quickshell.outfoxxed.me"

    log_info "Installing dependencies..."
    sudo dnf install -y "${DEPS_DNF[@]}"

    log_success "Dependencies installed"

    # ranger devicons plugin — provides file-type glyphs in the listing.
    local plug_dir="$CONFIG_DIR/ranger/plugins/ranger_devicons"
    if [[ ! -d "$plug_dir" ]]; then
        log_info "Installing ranger devicons plugin..."
        mkdir -p "$(dirname "$plug_dir")"
        git clone --depth 1 https://github.com/alexanderjeurissen/ranger_devicons "$plug_dir" >/dev/null 2>&1 &&
            log_success "ranger_devicons installed" ||
            log_warning "Failed to install ranger_devicons (network?)"
    fi
}

# Create symlinks via the single-source dots.sh.
create_symlinks() {
    log_info "Creating symlinks via dots.sh..."
    bash "$DOTS_DIR/dots.sh" backup --force

    # Avatar symlink: point ~/.config/hypr/avatar.png to AccountsService icon.
    local avatar_link="$HOME/.config/hypr/avatar.png"
    local avatar_source
    avatar_source="/var/lib/AccountsService/icons/$(whoami)"
    ln -sf "$avatar_source" "$avatar_link"
    log_success "Avatar symlink -> $avatar_source"
}

# Check optional external dependencies
check_optional_deps() {
    local env_target="$HOME/.config/scripts/util.env"
    if [[ ! -f "$env_target" ]]; then
        log_warning "scripts/util.env not present — copy util.env.example to populate"
        log_warning "  cp $HOME/.config/scripts/util.env.example $env_target"
    fi
}

# Install and configure Immich CLI
setup_immich_cli() {
    log_info "Setting up Immich CLI..."

    # Find a package manager
    local pm=""
    if command_exists bun; then
        pm="bun"
    elif command_exists npm; then
        pm="npm"
    else
        log_warning "Neither bun nor npm found — installing Node.js via dnf"
        sudo dnf install -y nodejs npm
        pm="npm"
    fi

    # Install @immich/cli globally
    if command_exists immich; then
        log_success "Immich CLI already installed ($(immich --version 2>/dev/null || echo 'unknown version'))"
    else
        log_info "Installing @immich/cli via $pm..."
        if [[ "$pm" == "bun" ]]; then
            bun install -g @immich/cli
        else
            npm install -g @immich/cli
        fi
        log_success "Immich CLI installed"
    fi

    # Wait for user to provide server URL and API key
    echo ""
    log_info "Configure Immich server connection"
    while true; do
        read -p "  Server URL (e.g. https://immich.example.com): " immich_url
        [[ -n "$immich_url" ]] && break
        log_warning "URL cannot be empty"
    done
    while true; do
        read -p "  API key (Immich → Account Settings → API Keys): " immich_key
        [[ -n "$immich_key" ]] && break
        log_warning "API key cannot be empty"
    done

    immich login "$immich_url/api" "$immich_key" &&
        log_success "Logged in to Immich" ||
        log_error "Login failed — check your URL and API key"

    # Prompt for sync interval and write it to the crontab via sync-toggle.sh.
    echo ""
    log_info "How often should Immich sync run?"
    echo "  1) Every 30 minutes"
    echo "  2) Every 1 hour"
    echo "  3) Every 2 hours"
    echo "  4) Every 6 hours"
    read -p "  Choose [1-4] (default: 2): " interval_choice
    echo

    local cron_expr="0 * * * *"
    case "$interval_choice" in
        1) cron_expr="*/30 * * * *" ;;
        2) cron_expr="0 * * * *" ;;
        3) cron_expr="0 */2 * * *" ;;
        4) cron_expr="0 */6 * * *" ;;
    esac

    bash "$DOTS_DIR/config/scripts/sync-toggle.sh" schedule immich "$cron_expr"
    log_success "Immich cron schedule: $cron_expr"

    read -p "Enable Immich background sync now? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        bash "$DOTS_DIR/config/scripts/sync-toggle.sh" enable immich
        log_success "Immich background sync enabled"
    fi
}

# Set up Jellyfin music sync
setup_jellyfin_sync() {
    log_info "Setting up Jellyfin music sync..."

    # Deploy the systemd user timer that runs the sync once a day. Real copies,
    # NOT symlinks — `systemctl disable` deletes a symlinked unit file, which
    # would break the Quick Actions toggle. The repo copies under systemd/user/
    # are the source of truth; re-run setup (or re-copy) after editing them.
    mkdir -p "$HOME/.config/systemd/user"
    cp "$DOTS_DIR/systemd/user/jellyfin-sync.service" "$HOME/.config/systemd/user/"
    cp "$DOTS_DIR/systemd/user/jellyfin-sync.timer" "$HOME/.config/systemd/user/"
    systemctl --user daemon-reload
    log_success "Jellyfin sync timer installed (once daily, Persistent — catches up missed runs)"

    # Prompt for credentials now
    local conf="$HOME/.config/jellyfin/sync.conf"
    if [[ ! -f "$conf" ]]; then
        log_info "Configure Jellyfin server connection"
        while true; do
            read -p "  Server URL (e.g. http://192.168.0.200:8096): " jf_url
            [[ -n "$jf_url" ]] && break
            log_warning "URL cannot be empty"
        done
        while true; do
            read -p "  API key (Jellyfin → Dashboard → API Keys): " jf_key
            [[ -n "$jf_key" ]] && break
            log_warning "API key cannot be empty"
        done
        mkdir -p "$(dirname "$conf")"
        cat >"$conf" <<EOF
JELLYFIN_URL="$jf_url"
JELLYFIN_API_KEY="$jf_key"
EOF
        chmod 600 "$conf"
        log_success "Jellyfin credentials saved"
    else
        log_success "Jellyfin credentials already configured"
    fi

    read -p "Enable Jellyfin background sync now? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        bash "$DOTS_DIR/config/scripts/sync-toggle.sh" enable jellyfin
        log_success "Jellyfin background sync enabled"
    fi
}

# Set up scripts permissions
setup_scripts() {
    log_info "Setting up script permissions..."

    if [[ -d "$DOTS_DIR/config/scripts" ]]; then
        # battery-charge-schedule has no .sh extension (it is deployed to
        # /usr/local/bin under that name), so the glob alone would skip it.
        chmod +x "$DOTS_DIR"/config/scripts/*.sh "$DOTS_DIR"/config/scripts/lib/*.sh \
            "$DOTS_DIR/config/scripts/battery-charge-schedule"
        log_success "Script permissions set"
    else
        log_warning "Scripts directory not found"
    fi
}

# Point git at the tracked hooks. .git/hooks is not version controlled, so the
# pre-commit check only exists for a clone that opts in.
setup_git_hooks() {
    if [[ ! -d "$DOTS_DIR/.git" ]]; then
        return 0
    fi

    log_info "Enabling the tracked git hooks..."
    chmod +x "$DOTS_DIR"/.githooks/*
    git -C "$DOTS_DIR" config core.hooksPath .githooks
    log_success "core.hooksPath set to .githooks"
}

# Nautilus thumbnailers live outside ~/.config, so the symlink manager skips
# them. Link each tracked entry into the user thumbnailer directory.
setup_thumbnailers() {
    local dest="$HOME/.local/share/thumbnailers"
    local entry

    log_info "Linking Nautilus thumbnailers..."
    mkdir -p "$dest"
    for entry in "$DOTS_DIR"/thumbnailers/*.thumbnailer; do
        ln -sf "$entry" "$dest/$(basename "$entry")"
    done
    log_success "Thumbnailers linked into $dest"
}

# Session daemon user units (battery-notify, power-auto, media/fullscreen
# inhibit). Installed and enabled; they start with the next graphical session.
setup_user_units() {
    log_info "Installing session daemon units..."
    if bash "$DOTS_DIR/dots.sh" units; then
        log_success "Session daemon units installed and enabled"
    else
        log_warning "Could not install the units (no systemd user session?). Re-run: dots.sh units"
    fi
}

# Root-owned battery charge-cap timer (Dell charge_types). Needs sudo.
setup_battery_timer() {
    log_info "Installing the battery charge timer via dots.sh..."
    if ! bash "$DOTS_DIR/dots.sh" system --force; then
        log_warning "Battery timer install failed. Re-run: dots.sh system"
    fi
}

# True when a battery exposes the charge_types file the script writes.
has_charge_types() {
    compgen -G "/sys/class/power_supply/BAT*/charge_types" >/dev/null
}

# Initial system setup
system_setup() {
    log_info "Running initial system setup..."

    # Set GTK dark theme
    if command_exists gsettings; then
        log_info "Setting GTK dark theme..."
        gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
        log_success "GTK theme configured"
    fi

    # Allow current user to manage Tailscale without sudo
    if command_exists tailscale; then
        log_info "Setting Tailscale operator to $USER..."
        sudo tailscale set --operator="$USER"
        log_success "Tailscale operator set to $USER"
    fi
}

# Create expected user directories
create_dirs() {
    log_info "Creating user directories..."
    local dirs=(
        "$HOME/Pictures/Screenshots"
        "$HOME/Pictures/wallpapers"
        "$HOME/Videos/Recordings"
        "$HOME/Music"
    )
    for d in "${dirs[@]}"; do
        mkdir -p "$d"
        log_success "Directory: $d"
    done
}

# Display setup summary
show_summary() {
    echo ""
    echo "========================================"
    echo "  Dotfiles Setup Complete!"
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo "1. Log out and log back into Hyprland"
    echo "2. Drop wallpapers into ~/Pictures/wallpapers"
    echo "3. Review keybindings in hypr/modules/keys.lua"
    echo "4. Customize colors and themes to your liking"
    echo ""
    echo "Useful commands:"
    echo "  - Super+B: Restart all services"
    echo "  - Super+Shift+N: Change wallpaper"
    echo "  - Super+R: Open app launcher"
    echo ""
    echo "  - immich login <url>/api <key>: Configure Immich CLI"
    echo "For more info, see README.md"
    echo "========================================"
}

# Main installation flow
setup_avatar() {
    log_info "Generating initials avatar..."
    if ! command_exists python3; then
        log_warning "python3 not found, skipping avatar generation"
        return
    fi
    if ! python3 -c "from PIL import Image" 2>/dev/null; then
        log_warning "python3-pillow not found, skipping avatar generation"
        return
    fi

    bash "$CONFIG_DIR/scripts/generate-avatar.sh" &&
        log_success "Avatar installed to /var/lib/AccountsService/icons/$(whoami)" ||
        log_warning "Avatar generation failed"
}

# Full first-time setup. Safe to re-run: symlinks, units, directories and
# permissions are re-applied idempotently. Credential-driven steps (Immich,
# Jellyfin) are skipped with --yes.
cmd_setup() {
    set -e

    # Shared dependency list (also used by scripts/doctor.sh).
    source "$DOTS_DIR/config/scripts/lib/deps.sh"

    echo "========================================"
    echo "  Hyprland Dotfiles Setup"
    echo "========================================"
    echo ""

    # Check dependencies
    if ! check_setup_dependencies; then
        if ask "Install missing dependencies? (y/N)" N; then
            install_dependencies || {
                log_error "Failed to install dependencies"
                exit 1
            }
        else
            log_warning "Proceeding without installing dependencies"
        fi
    fi

    # Confirm before creating symlinks
    echo ""
    if ask "Create symlinks for config directories? (Y/n)" Y; then
        create_symlinks
    fi

    # Check optional dependencies
    check_optional_deps

    # Create expected directories
    create_dirs

    # Set up scripts
    setup_scripts

    # Enable the tracked git hooks
    setup_git_hooks

    # Nautilus thumbnailers
    setup_thumbnailers

    # Session daemons as systemd user units
    echo ""
    if ask "Install and enable the session daemon units (battery, power, idle inhibitors)? (Y/n)" Y; then
        setup_user_units
    fi

    # Root-owned battery charge timer
    echo ""
    if [[ "$ASSUME_YES" == true ]] && ! has_charge_types; then
        log_info "No battery with charge_types found, skipping the battery charge timer"
    elif ask "Install the root battery charge timer (needs sudo)? (y/N)" N; then
        setup_battery_timer
    fi

    # System setup
    echo ""
    if ask "Run initial system setup (GTK theme)? (Y/n)" Y; then
        system_setup
    fi

    # Credential-driven steps need typed input, so --yes skips them.
    echo ""
    if [[ "$ASSUME_YES" == true ]]; then
        log_info "--yes: skipping Immich/Jellyfin setup (needs credentials); run dots.sh setup interactively for those"
    else
        if ask "Install and configure Immich CLI? (y/N)" N; then
            setup_immich_cli
        fi

        echo ""
        if ask "Set up Jellyfin music sync? (y/N)" N; then
            setup_jellyfin_sync
        fi
    fi

    # Generate avatar
    echo ""
    if ask "Generate initials avatar for lockscreen? (Y/n)" Y; then
        setup_avatar
    fi

    # Show summary
    show_summary
}

################################################################################
# Install (curl bootstrap: clone the repo, then run setup)
################################################################################

cmd_install() {
    local repo="https://github.com/Gren-95/hyprland-dots.git"
    local dest="$HOME/dotfiles"

    echo "========================================="
    echo "  hyprland-dots installer"
    echo "========================================="
    echo ""

    if ! command -v git >/dev/null 2>&1; then
        log_info "Installing git..."
        sudo dnf install -y git
    fi

    if [[ -d "$dest/.git" ]]; then
        log_info "Dotfiles already cloned, pulling latest..."
        git -C "$dest" pull
    else
        if [[ -d "$dest" ]]; then
            log_error "$dest already exists but is not a git repo. Remove it and try again."
            exit 1
        fi
        log_info "Cloning dotfiles to $dest..."
        git clone "$repo" "$dest"
    fi

    log_success "Repo ready at $dest"
    echo ""

    local args=(setup)
    [[ "$ASSUME_YES" == true ]] && args+=(--yes)
    exec bash "$dest/dots.sh" "${args[@]}"
}

################################################################################
# Main
################################################################################

show_usage() {
    cat <<EOF
Hyprland dotfiles installer, setup and symlink manager

Usage: $(basename "$0") <command> [options]

Commands:
  install   Clone the repo to ~/dotfiles and run setup (curl one-liner entry point)
  setup     Install dependencies, symlinks, units and one-time system config
  backup    Create backups and symlinks
  undo      Restore backups and remove symlinks
  status    Show current symlink status
  fix       Fix inconsistent symlink paths
  prune     Remove dangling ~/.config symlinks pointing into this repo
  system    Install root-owned scripts and systemd units (needs sudo)
  units     Install and enable the session daemon user units (no sudo)

Options:
  -y, --yes    Non-interactive setup: answer yes to every prompt. Steps that
               need credentials typed in (Immich, Jellyfin) are skipped.
  --dry-run    Preview changes without executing
  --force      Skip confirmation prompts
  --verbose    Show detailed output
  -h, --help   Show this help message

Examples:
  $(basename "$0") setup --yes         # Unattended first-time setup
  $(basename "$0") backup --dry-run    # Preview backup operation
  $(basename "$0") status              # Check symlink status
  $(basename "$0") fix                 # Fix inconsistent symlinks
  $(basename "$0") undo                # Undo last operation
  $(basename "$0") system              # Install system scripts and units
  $(basename "$0") units               # Install session daemon user units

EOF
}

main() {
    local command=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            install | setup | backup | undo | status | fix | prune | system | units)
                command="$1"
                shift
                ;;
            -y | --yes)
                ASSUME_YES=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h | --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    if [[ -z "$command" ]]; then
        log_error "No command specified"
        show_usage
        exit 1
    fi

    case "$command" in
        install)
            cmd_install
            return
            ;;
        setup)
            verify_dots_dir
            cmd_setup
            return
            ;;
    esac

    check_manager_tools
    verify_dots_dir

    # Acquire lock (except for status command)
    if [[ "$command" != "status" ]]; then
        acquire_lock
    fi

    case "$command" in
        backup) cmd_backup ;;
        undo) cmd_undo ;;
        status) cmd_status ;;
        fix) cmd_fix ;;
        prune) cmd_prune ;;
        system) cmd_system ;;
        units) cmd_units ;;
    esac
}

main "$@"
