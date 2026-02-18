# Dotfiles Manager - Quick Reference

## Overview

The `dotfiles-manager.sh` script manages your dotfiles by creating symlinks from this repository to `~/.config/` and backing up existing configurations.

## Managed Folders

- hypr
- kitty
- waybar
- swaync
- swayosd
- swappy

## Commands

### Check Status
```bash
./dotfiles-manager.sh status
```
Shows the current state of all symlinks.

### Create Backups and Symlinks
```bash
# Preview changes first (recommended)
./dotfiles-manager.sh backup --dry-run

# Execute the backup
./dotfiles-manager.sh backup
```
- Backs up existing directories with timestamp (e.g., `hypr_bak_20260214_201946`)
- Creates symlinks from this repo to `~/.config/`
- Logs all operations to `~/.config/.dotfiles_symlink.log`

### Fix Inconsistent Symlinks
```bash
./dotfiles-manager.sh fix
```
Standardizes all symlinks to use the canonical path.

### Undo Last Operation
```bash
./dotfiles-manager.sh undo
```
- Removes symlinks
- Restores backups to original names
- Archives the log file

## Options

- `--dry-run` - Preview changes without executing
- `--force` - Skip confirmation prompts
- `--verbose` - Show detailed output

## Examples

### Initial Setup
```bash
# Check current status
./dotfiles-manager.sh status

# Preview what will happen
./dotfiles-manager.sh backup --dry-run

# Create backups and symlinks
./dotfiles-manager.sh backup
```

### After Updates
```bash
# Check if any symlinks are broken or inconsistent
./dotfiles-manager.sh status

# Fix any issues
./dotfiles-manager.sh fix
```

### Rolling Back
```bash
# Restore everything to pre-symlink state
./dotfiles-manager.sh undo
```

## Safety Features

1. **Lock File** - Prevents concurrent execution
2. **Dry-Run Mode** - Preview changes before applying
3. **Timestamped Backups** - Multiple backup versions for safety
4. **Atomic Operations** - Rollback on failure
5. **JSON Log** - Complete audit trail
6. **Confirmation Prompts** - User approval for destructive operations

## Log File

Location: `~/.config/.dotfiles_symlink.log`

Contains JSON with all operations:
```json
{
  "version": "1.0",
  "operations": [
    {
      "item": "swayosd",
      "action": "symlink",
      "backup_path": "",
      "timestamp": "20260214_201946"
    }
  ],
  "last_backup": "20260214_201946"
}
```

## Troubleshooting

### "Lock file exists" error
Another instance is running or crashed. Remove the lock file:
```bash
rm /tmp/dotfiles-manager.lock
```

### Symlink points to wrong path
Run the fix command:
```bash
./dotfiles-manager.sh fix
```

### Want to restore a specific backup manually
Backups are named with timestamps:
```bash
ls ~/.config/*_bak_*
mv ~/.config/hypr_bak_20260214_201946 ~/.config/hypr
```

## Current Status

All 9 config folders are now properly symlinked:
```
✓ hypr      → /mnt/DATA/Home_Folders/Documents/dots/hypr
✓ kitty     → /mnt/DATA/Home_Folders/Documents/dots/kitty
✓ waybar    → /mnt/DATA/Home_Folders/Documents/dots/waybar
✓ swaync    → /mnt/DATA/Home_Folders/Documents/dots/swaync
✓ swayosd   → /mnt/DATA/Home_Folders/Documents/dots/swayosd
✓ swappy    → /mnt/DATA/Home_Folders/Documents/dots/swappy
```
