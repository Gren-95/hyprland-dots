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
    "rofi"
    "fish"
    "nvim"
    "ranger"
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
        "tesseract" "convert" "rofi" "cliphist" "wl-copy" "wl-paste" "swayosd-server" "waybar"
        "firefox" "brightnessctl" "playerctl" "pavucontrol"
        "gnome-keyring-daemon" "jq" "pactl" "wpctl" "python3" "fish" "nvim" "ranger"
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
    sudo dnf copr enable -y erikreider/SwayNotificationCenter
    sudo dnf copr enable -y washkinazy/wayland-wm-extras

    print_info "Installing dependencies..."
    sudo dnf install -y \
        hyprland hyprland-devel kitty nautilus cliphist \
        hyprpaper hyprpicker hypridle swaync grim slurp \
        swappy tesseract tesseract-langpack-est ImageMagick wl-clipboard swayosd waybar firefox rofi \
        brightnessctl playerctl pavucontrol hyprpolkitagent network-manager-applet \
        gnome-calendar gnome-keyring jq \
        powerprofilesctl hyprlock gpu-screen-recorder \
        fish neovim ranger python3 python3-pillow

    print_success "Dependencies installed"

    # Install Trayscale (Tailscale GUI tray applet)
    if command_exists flatpak; then
        print_info "Installing Trayscale (Tailscale GUI)..."
        flatpak install -y flathub dev.deedles.Trayscale
        print_success "Trayscale installed"
    else
        print_warning "flatpak not found — skipping Trayscale install"
    fi
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

    # Waybar active config symlinks — default to floating style
    local waybar_dir="$HOME/.config/waybar"
    [[ ! -e "$waybar_dir/config-active" ]] && \
        ln -sf "$waybar_dir/config" "$waybar_dir/config-active" && \
        print_success "Waybar config-active -> config (floating)"
    [[ ! -e "$waybar_dir/style-active.css" ]] && \
        ln -sf "$waybar_dir/style.css" "$waybar_dir/style-active.css" && \
        print_success "Waybar style-active.css -> style.css (floating)"

    # Avatar symlink: point ~/.config/hypr/avatar.png to AccountsService icon
    local avatar_link="$HOME/.config/hypr/avatar.png"
    local avatar_source="/var/lib/AccountsService/icons/$(whoami)"
    ln -sf "$avatar_source" "$avatar_link"
    print_success "Avatar symlink -> $avatar_source"
}

# Check optional external dependencies
check_optional_deps() {
    if [[ ! -f "$HOME/Documents/Code/linux-sysutil/cli_tool.py" ]]; then
        print_warning "linux-sysutil not found at ~/Documents/Code/linux-sysutil/"
        print_warning "Super+Shift+M/K keybinds will not work without it"
        print_warning "Clone it from: https://github.com/Gren-95/linux-sysutil"
    fi
}

# Install and configure Immich CLI
setup_immich_cli() {
    print_info "Setting up Immich CLI..."

    # Find a package manager
    local pm=""
    if command_exists bun; then
        pm="bun"
    elif command_exists npm; then
        pm="npm"
    else
        print_warning "Neither bun nor npm found — installing Node.js via dnf"
        sudo dnf install -y nodejs npm
        pm="npm"
    fi

    # Install @immich/cli globally
    if command_exists immich; then
        print_success "Immich CLI already installed ($(immich --version 2>/dev/null || echo 'unknown version'))"
    else
        print_info "Installing @immich/cli via $pm..."
        if [[ "$pm" == "bun" ]]; then
            bun install -g @immich/cli
        else
            npm install -g @immich/cli
        fi
        print_success "Immich CLI installed"
    fi

    # Wait for user to provide server URL and API key
    echo ""
    print_info "Configure Immich server connection"
    while true; do
        read -p "  Server URL (e.g. https://immich.example.com): " immich_url
        [[ -n "$immich_url" ]] && break
        print_warning "URL cannot be empty"
    done
    while true; do
        read -p "  API key (Immich → Account Settings → API Keys): " immich_key
        [[ -n "$immich_key" ]] && break
        print_warning "API key cannot be empty"
    done

    immich login "$immich_url/api" "$immich_key" && \
        print_success "Logged in to Immich" || \
        print_error "Login failed — check your URL and API key"

    # Prompt for sync interval
    echo ""
    print_info "How often should Immich sync run?"
    echo "  1) Every 30 minutes"
    echo "  2) Every 1 hour"
    echo "  3) Every 2 hours"
    echo "  4) Every 6 hours"
    read -p "  Choose [1-4] (default: 2): " interval_choice
    echo

    local sleep_secs=3600
    case "$interval_choice" in
        1) sleep_secs=1800  ;;
        2) sleep_secs=3600  ;;
        3) sleep_secs=7200  ;;
        4) sleep_secs=21600 ;;
        *) sleep_secs=3600  ;;
    esac

    local sync_script="$CONFIG_DIR/scripts/immich-sync.sh"
    if [[ -f "$sync_script" ]]; then
        sed -i "s/sleep [0-9]*/sleep $sleep_secs/" "$sync_script"
        print_success "Immich sync interval set to $sleep_secs seconds"
    fi
}

# Set up Jellyfin music sync
setup_jellyfin_sync() {
    print_info "Setting up Jellyfin music sync..."

    local autostart="$CONFIG_DIR/hypr/modules/autostart.conf"

    # Prompt for sync interval
    echo ""
    print_info "How often should music sync run?"
    echo "  1) Every 30 minutes"
    echo "  2) Every 1 hour"
    echo "  3) Every 2 hours"
    echo "  4) Every 6 hours"
    read -p "  Choose [1-4] (default: 3): " interval_choice
    echo

    local sleep_secs=7200
    case "$interval_choice" in
        1) sleep_secs=1800  ;;
        2) sleep_secs=3600  ;;
        3) sleep_secs=7200  ;;
        4) sleep_secs=21600 ;;
        *) sleep_secs=7200  ;;
    esac

    # Write the interval into the sync script
    local sync_script="$CONFIG_DIR/scripts/jellyfin-music-sync.sh"
    if [[ -f "$sync_script" ]]; then
        sed -i "s/sleep [0-9]*/sleep $sleep_secs/" "$sync_script"
        print_success "Sync interval set to $sleep_secs seconds"
    fi

    # Add to autostart if not already present
    if [[ -f "$autostart" ]] && ! grep -q "jellyfin-music-sync" "$autostart"; then
        echo "exec-once = bash ~/.config/scripts/jellyfin-music-sync.sh --daemon" >> "$autostart"
        print_success "Added Jellyfin sync to Hyprland autostart"
    fi

    # Prompt for credentials now
    local conf="$HOME/.config/jellyfin/sync.conf"
    if [[ ! -f "$conf" ]]; then
        print_info "Configure Jellyfin server connection"
        while true; do
            read -p "  Server URL (e.g. http://192.168.0.200:8096): " jf_url
            [[ -n "$jf_url" ]] && break
            print_warning "URL cannot be empty"
        done
        while true; do
            read -p "  API key (Jellyfin → Dashboard → API Keys): " jf_key
            [[ -n "$jf_key" ]] && break
            print_warning "API key cannot be empty"
        done
        mkdir -p "$(dirname "$conf")"
        cat > "$conf" <<EOF
JELLYFIN_URL="$jf_url"
JELLYFIN_API_KEY="$jf_key"
EOF
        chmod 600 "$conf"
        print_success "Jellyfin credentials saved"
    else
        print_success "Jellyfin credentials already configured"
    fi
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

    # Allow current user to manage Tailscale without sudo
    if command_exists tailscale; then
        print_info "Setting Tailscale operator to $USER..."
        sudo tailscale set --operator="$USER"
        print_success "Tailscale operator set to $USER"
    fi
}

# Create expected user directories
create_dirs() {
    print_info "Creating user directories..."
    local dirs=(
        "$HOME/Pictures/Screenshots"
        "$HOME/Pictures/wallpapers"
        "$HOME/Videos/Recordings"
        "$HOME/Music"
    )
    for d in "${dirs[@]}"; do
        mkdir -p "$d"
        print_success "Directory: $d"
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
    echo "2. Configure wallpapers in scripts/wallpaper.sh"
    echo "3. Review keybindings in hypr/modules/keys.conf"
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
    print_info "Generating initials avatar..."
    if ! command_exists python3; then
        print_warning "python3 not found, skipping avatar generation"
        return
    fi
    if ! python3 -c "from PIL import Image" 2>/dev/null; then
        print_warning "python3-pillow not found, skipping avatar generation"
        return
    fi

    bash "$CONFIG_DIR/scripts/generate-avatar.sh" && \
        print_success "Avatar installed to /var/lib/AccountsService/icons/$(whoami)" || \
        print_warning "Avatar generation failed"
}

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

    # Check optional dependencies
    check_optional_deps

    # Create expected directories
    create_dirs

    # Set up scripts
    setup_scripts

    # System setup
    echo ""
    read -p "Run initial system setup (GTK theme, SwayOSD)? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        system_setup
    fi

    # Optional: Immich CLI
    echo ""
    read -p "Install and configure Immich CLI? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_immich_cli
    fi

    # Optional: Jellyfin music sync
    echo ""
    read -p "Set up Jellyfin music sync? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_jellyfin_sync
    fi

    # Generate avatar
    echo ""
    read -p "Generate initials avatar for lockscreen? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        setup_avatar
    fi

    # Show summary
    show_summary
}

# Run main function
main "$@"
