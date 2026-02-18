#!/bin/bash

################################################################################
# Dotfiles Backup and Symlink Manager
# Manages symlinks from dotfiles repository to ~/.config/
################################################################################

# Constants
DOTS_DIR="/mnt/DATA/Home_Folders/Documents/dots"
CONFIG_DIR="$HOME/.config"
LOG_FILE="$CONFIG_DIR/.dotfiles_symlink.log"
LOCK_FILE="/tmp/dotfiles-manager.lock"

# Config items to manage
CONFIG_ITEMS=(
    "hypr"
    "kitty"
    "nvim"
    "vim"
    "waybar"
    "swaync"
    "swayosd"
    "swappy"
)

# Options
DRY_RUN=false
FORCE=false
VERBOSE=false

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
    echo $$ > "$LOCK_FILE"
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
check_dependencies() {
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
    local available=$(df -BM "$CONFIG_DIR" | awk 'NR==2 {print $4}' | sed 's/M//')
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
    local timestamp=$(get_timestamp)
    cat > "$LOG_FILE" <<EOF
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
    local timestamp=$(get_timestamp)

    if [[ "$DRY_RUN" == true ]]; then
        return
    fi

    # Create log if it doesn't exist
    if [[ ! -f "$LOG_FILE" ]]; then
        init_log
    fi

    # Add operation to log
    local temp_log=$(mktemp)
    jq --arg item "$item" \
       --arg action "$action" \
       --arg backup "$backup_path" \
       --arg time "$timestamp" \
       '.operations += [{
           "item": $item,
           "action": $action,
           "backup_path": $backup,
           "timestamp": $time
       }] | .last_backup = $time' "$LOG_FILE" > "$temp_log"

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
    local source="$DOTS_DIR/$item"
    local canonical_source=$(get_canonical_path "$source")

    if [[ ! -e "$target" && ! -L "$target" ]]; then
        echo "MISSING"
    elif [[ -L "$target" ]]; then
        local link_target=$(readlink "$target")
        local canonical_link=$(get_canonical_path "$target")

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
    local timestamp=$(get_timestamp)
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
    local source="$DOTS_DIR/$item"
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
    local canonical_target=$(get_canonical_path "$target")
    local canonical_source=$(get_canonical_path "$source")

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
        local source="$DOTS_DIR/$item"
        local target="$CONFIG_DIR/$item"
        local status=$(check_symlink "$item")

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

            INCONSISTENT|BROKEN)
                log_info "Fixing symlink: $item"
                remove_symlink "$item" || { ((failed++)); continue; }
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
    local operations=$(jq -r '.operations | length' "$LOG_FILE")

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
        local item=$(echo "$op" | jq -r '.item')
        local action=$(echo "$op" | jq -r '.action')
        local backup_path=$(echo "$op" | jq -r '.backup_path')

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
        local archive="${LOG_FILE}.$(get_timestamp)"
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
        local status=$(check_symlink "$item")
        local target="$CONFIG_DIR/$item"
        local details=""

        case "$status" in
            OK)
                details="${GREEN}Symlink OK${NC}"
                ((ok++))
                ;;
            INCONSISTENT)
                local link_target=$(readlink "$target")
                details="${YELLOW}Points to: $link_target${NC}"
                ((issues++))
                ;;
            BROKEN)
                local link_target=$(readlink "$target")
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
        echo "  - Run 'dotfiles-manager.sh fix' to fix inconsistent symlinks"
        echo "  - Run 'dotfiles-manager.sh backup' to create missing symlinks"
    fi
}

cmd_fix() {
    log_info "Fixing inconsistent symlinks..."

    verify_dots_dir

    local fixed=0
    local failed=0
    local skipped=0

    for item in "${CONFIG_ITEMS[@]}"; do
        local status=$(check_symlink "$item")

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

################################################################################
# Main
################################################################################

show_usage() {
    cat <<EOF
Dotfiles Backup and Symlink Manager

Usage: $(basename "$0") <command> [options]

Commands:
  backup    Create backups and symlinks
  undo      Restore backups and remove symlinks
  status    Show current symlink status
  fix       Fix inconsistent symlink paths

Options:
  --dry-run    Preview changes without executing
  --force      Skip confirmation prompts
  --verbose    Show detailed output
  -h, --help   Show this help message

Examples:
  $(basename "$0") backup --dry-run    # Preview backup operation
  $(basename "$0") backup               # Create backups and symlinks
  $(basename "$0") status               # Check symlink status
  $(basename "$0") fix                  # Fix inconsistent symlinks
  $(basename "$0") undo                 # Undo last operation

EOF
}

main() {
    # Parse command
    local command=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            backup|undo|status|fix)
                command="$1"
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
            -h|--help)
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

    # Check dependencies
    check_dependencies

    # Acquire lock (except for status command)
    if [[ "$command" != "status" ]]; then
        acquire_lock
    fi

    # Execute command
    case "$command" in
        backup)
            cmd_backup
            ;;
        undo)
            cmd_undo
            ;;
        status)
            cmd_status
            ;;
        fix)
            cmd_fix
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
