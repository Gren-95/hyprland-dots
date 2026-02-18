#!/bin/bash
# Hyprland Dotfiles Setup Script
# Automates installation of dependencies and configuration

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration directories to symlink
CONFIG_ITEMS=(
    "hypr"
    "kitty"
    "waybar"
    "swaync"
    "swayosd"
    "swappy"
    "scripts"
    "wayvnc"
    "gtklock"
)

# Print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running on Fedora/Nobara
check_distro() {
    if [[ -f /etc/fedora-release ]] || [[ -f /etc/nobara-release ]]; then
        return 0
    else
        print_warning "This script is optimized for Fedora/Nobara"
        return 1
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check dependencies
check_dependencies() {
    print_info "Checking dependencies..."

    local missing_deps=()
    local required_deps=(
        "hyprland" "kitty" "nautilus" "hyprpaper" "hyprpicker"
        "hypridle" "swaync" "grim" "slurp" "swappy"
        "tesseract" "wl-copy" "swayosd-server" "waybar"
        "firefox" "brightnessctl" "playerctl" "pavucontrol"
        "nm-applet" "gnome-keyring" "vicinae"
    )

    for dep in "${required_deps[@]}"; do
        if ! command_exists "$dep"; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        print_success "All dependencies are installed"
        return 0
    else
        print_warning "Missing dependencies: ${missing_deps[*]}"
        return 1
    fi
}

# Install dependencies (Fedora/Nobara)
install_dependencies() {
    if ! check_distro; then
        print_error "Automatic installation only supported on Fedora/Nobara"
        return 1
    fi

    print_info "Adding required COPR repositories..."
    sudo dnf copr enable -y lionheartp/Hyprland
    sudo dnf copr enable -y azandure/clipse
    sudo dnf copr enable -y erikreider/SwayNotificationCenter
    sudo dnf copr enable -y washkinazy/wayland-wm-extras
    sudo dnf copr enable -y quadratech188/vicinae

    print_info "Installing dependencies..."
    sudo dnf install -y \
        hyprland kitty nautilus clipse \
        hyprpaper hyprpicker hypridle swaync grim slurp \
        swappy tesseract wl-clipboard swayosd waybar firefox \
        brightnessctl playerctl pavucontrol polkit-gnome \
        network-manager-applet gnome-calendar gnome-keyring \
        powerprofilesctl gtklock gtklock-meta \
        gtklock-playerctl-module gtklock-userinfo-module vicinae

    print_success "Dependencies installed"
}

# Create backup of existing config
backup_config() {
    local item="$1"
    local target="$CONFIG_DIR/$item"

    if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
        local backup_name="${item}_backup_$(date +%Y%m%d_%H%M%S)"
        print_info "Backing up existing $item to $backup_name"
        mv "$target" "$CONFIG_DIR/$backup_name"
        print_success "Backed up $item"
    fi
}

# Create symlinks
create_symlinks() {
    print_info "Creating symlinks..."

    for item in "${CONFIG_ITEMS[@]}"; do
        local source="$SCRIPT_DIR/$item"
        local target="$CONFIG_DIR/$item"

        # Check if source exists
        if [[ ! -e "$source" ]]; then
            print_warning "Skipping $item (not found in dotfiles)"
            continue
        fi

        # Handle existing target
        if [[ -L "$target" ]]; then
            # Already a symlink
            local current_target=$(readlink -f "$target")
            local expected_target=$(readlink -f "$source")

            if [[ "$current_target" == "$expected_target" ]]; then
                print_success "$item already correctly symlinked"
                continue
            else
                print_info "Updating symlink for $item"
                rm "$target"
            fi
        elif [[ -e "$target" ]]; then
            # Exists but not a symlink - backup first
            backup_config "$item"
        fi

        # Create symlink
        ln -sf "$source" "$target"
        print_success "Symlinked $item"
    done
}

# Set up scripts permissions
setup_scripts() {
    print_info "Setting up script permissions..."

    if [[ -d "$SCRIPT_DIR/scripts" ]]; then
        chmod +x "$SCRIPT_DIR"/scripts/*.sh
        print_success "Script permissions set"
    else
        print_warning "Scripts directory not found"
    fi
}

# Initial system setup
system_setup() {
    print_info "Running initial system setup..."

    # Enable SwayOSD service
    if command_exists swayosd-server; then
        print_info "Enabling SwayOSD libinput backend..."
        sudo systemctl enable --now swayosd-libinput-backend.service 2>/dev/null || true
        print_success "SwayOSD service enabled"
    fi

    # Set GTK dark theme
    if command_exists gsettings; then
        print_info "Setting GTK dark theme..."
        gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
        print_success "GTK theme configured"
    fi
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
    echo "2. Configure wallpapers in scripts/wallpaper.sh"
    echo "3. Review keybindings in hypr/modules/keys.conf"
    echo "4. Customize colors and themes to your liking"
    echo ""
    echo "Useful commands:"
    echo "  - Super+B: Restart all services"
    echo "  - Super+Shift+N: Change wallpaper"
    echo "  - Super+R: Open app launcher"
    echo ""
    echo "For more info, see README.md"
    echo "========================================"
}

# Main installation flow
main() {
    echo "========================================"
    echo "  Hyprland Dotfiles Setup"
    echo "========================================"
    echo ""

    # Check dependencies
    if ! check_dependencies; then
        read -p "Install missing dependencies? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_dependencies || {
                print_error "Failed to install dependencies"
                exit 1
            }
        else
            print_warning "Proceeding without installing dependencies"
        fi
    fi

    # Confirm before creating symlinks
    echo ""
    read -p "Create symlinks for config directories? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        create_symlinks
    fi

    # Set up scripts
    setup_scripts

    # System setup
    echo ""
    read -p "Run initial system setup (GTK theme, SwayOSD)? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        system_setup
    fi

    # Show summary
    show_summary
}

# Run main function
main "$@"
