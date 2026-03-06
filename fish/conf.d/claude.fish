# Claude Code - XDG Base Directory compliance
# ~/.claude is a symlink -> ~/.config/claude (works regardless of launch context)
# CLAUDE_CONFIG_DIR is kept as belt-and-suspenders for shells that resolve symlinks differently
# See: https://github.com/anthropics/claude-code/issues/1455
set -gx CLAUDE_CONFIG_DIR "$HOME/.config/claude"
