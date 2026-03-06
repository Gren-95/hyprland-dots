#!/bin/bash
# One-command installer for hyprland-dots
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/Gren-95/hyprland-dots/main/install.sh)

set -e

REPO="https://github.com/Gren-95/hyprland-dots.git"
DEST="$HOME/dotfiles"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================="
echo "  hyprland-dots installer"
echo "========================================="
echo ""

# Ensure git is available
if ! command -v git >/dev/null 2>&1; then
    print_info "Installing git..."
    sudo dnf install -y git
fi

# Clone or update repo
if [[ -d "$DEST/.git" ]]; then
    print_info "Dotfiles already cloned, pulling latest..."
    git -C "$DEST" pull
else
    if [[ -d "$DEST" ]]; then
        print_error "$DEST already exists but is not a git repo. Remove it and try again."
        exit 1
    fi
    print_info "Cloning dotfiles to $DEST..."
    git clone "$REPO" "$DEST"
fi

print_success "Repo ready at $DEST"
echo ""

# Run setup
chmod +x "$DEST/setup.sh"
cd "$DEST"
bash setup.sh
