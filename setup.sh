#!/bin/bash
# Hyprland Dotfiles Setup Script
# Automates installation of dependencies and configuration.
#
# Usage: setup.sh [--yes]
#   --yes, -y   Non-interactive: answer yes to every prompt. Steps that need
#               credentials typed in (Immich, Jellyfin) are skipped.
#
# Safe to re-run: symlinks, units, directories and permissions are re-applied
# idempotently.

set -e # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"
ASSUME_YES=false

# Shared dependency list (also used by scripts/doctor.sh).
source "$SCRIPT_DIR/scripts/lib/deps.sh"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Config directories to symlink are owned by dotfiles-manager.sh — single
# source of truth. setup.sh shells out to it.

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
check_dependencies() {
    print_info "Checking dependencies..."

    local missing_deps=()
    mapfile -t missing_deps < <(deps_missing_required)
    if ! deps_have_pygobject; then
        missing_deps+=("python3-gobject")
    fi

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
    sudo dnf copr enable -y errornointernet/quickshell ||
        print_warning "Quickshell COPR not available — build from source: https://quickshell.outfoxxed.me"

    print_info "Installing dependencies..."
    sudo dnf install -y "${DEPS_DNF[@]}"

    print_success "Dependencies installed"

    # ranger devicons plugin — provides file-type glyphs in the listing.
    local plug_dir="$CONFIG_DIR/ranger/plugins/ranger_devicons"
    if [[ ! -d "$plug_dir" ]]; then
        print_info "Installing ranger devicons plugin..."
        mkdir -p "$(dirname "$plug_dir")"
        git clone --depth 1 https://github.com/alexanderjeurissen/ranger_devicons "$plug_dir" >/dev/null 2>&1 &&
            print_success "ranger_devicons installed" ||
            print_warning "Failed to install ranger_devicons (network?)"
    fi
}

# Create symlinks via the single-source dotfiles-manager.sh.
create_symlinks() {
    print_info "Creating symlinks via dotfiles-manager.sh..."
    bash "$SCRIPT_DIR/dotfiles-manager.sh" backup --force

    # Avatar symlink: point ~/.config/hypr/avatar.png to AccountsService icon.
    local avatar_link="$HOME/.config/hypr/avatar.png"
    local avatar_source
    avatar_source="/var/lib/AccountsService/icons/$(whoami)"
    ln -sf "$avatar_source" "$avatar_link"
    print_success "Avatar symlink -> $avatar_source"
}

# Check optional external dependencies
check_optional_deps() {
    local env_target="$HOME/.config/scripts/util.env"
    if [[ ! -f "$env_target" ]]; then
        print_warning "scripts/util.env not present — copy util.env.example to populate"
        print_warning "  cp $HOME/.config/scripts/util.env.example $env_target"
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

    immich login "$immich_url/api" "$immich_key" &&
        print_success "Logged in to Immich" ||
        print_error "Login failed — check your URL and API key"

    # Prompt for sync interval and write it to the crontab via sync-toggle.sh.
    echo ""
    print_info "How often should Immich sync run?"
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

    bash "$SCRIPT_DIR/scripts/sync-toggle.sh" schedule immich "$cron_expr"
    print_success "Immich cron schedule: $cron_expr"

    read -p "Enable Immich background sync now? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        bash "$SCRIPT_DIR/scripts/sync-toggle.sh" enable immich
        print_success "Immich background sync enabled"
    fi
}

# Set up Jellyfin music sync
setup_jellyfin_sync() {
    print_info "Setting up Jellyfin music sync..."

    # Deploy the systemd user timer that runs the sync once a day. Real copies,
    # NOT symlinks — `systemctl disable` deletes a symlinked unit file, which
    # would break the Quick Actions toggle. The repo copies under systemd/user/
    # are the source of truth; re-run setup (or re-copy) after editing them.
    mkdir -p "$HOME/.config/systemd/user"
    cp "$SCRIPT_DIR/systemd/user/jellyfin-sync.service" "$HOME/.config/systemd/user/"
    cp "$SCRIPT_DIR/systemd/user/jellyfin-sync.timer" "$HOME/.config/systemd/user/"
    systemctl --user daemon-reload
    print_success "Jellyfin sync timer installed (once daily, Persistent — catches up missed runs)"

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
        cat >"$conf" <<EOF
JELLYFIN_URL="$jf_url"
JELLYFIN_API_KEY="$jf_key"
EOF
        chmod 600 "$conf"
        print_success "Jellyfin credentials saved"
    else
        print_success "Jellyfin credentials already configured"
    fi

    read -p "Enable Jellyfin background sync now? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        bash "$SCRIPT_DIR/scripts/sync-toggle.sh" enable jellyfin
        print_success "Jellyfin background sync enabled"
    fi
}

# Set up scripts permissions
setup_scripts() {
    print_info "Setting up script permissions..."

    if [[ -d "$SCRIPT_DIR/scripts" ]]; then
        # battery-charge-schedule has no .sh extension (it is deployed to
        # /usr/local/bin under that name), so the glob alone would skip it.
        chmod +x "$SCRIPT_DIR"/scripts/*.sh "$SCRIPT_DIR"/scripts/lib/*.sh \
            "$SCRIPT_DIR/scripts/battery-charge-schedule"
        print_success "Script permissions set"
    else
        print_warning "Scripts directory not found"
    fi
}

# Point git at the tracked hooks. .git/hooks is not version controlled, so the
# pre-commit check only exists for a clone that opts in.
setup_git_hooks() {
    if [[ ! -d "$SCRIPT_DIR/.git" ]]; then
        return 0
    fi

    print_info "Enabling the tracked git hooks..."
    chmod +x "$SCRIPT_DIR"/.githooks/*
    git -C "$SCRIPT_DIR" config core.hooksPath .githooks
    print_success "core.hooksPath set to .githooks"
}

# Session daemon user units (battery-notify, power-auto, media/fullscreen
# inhibit). Installed and enabled; they start with the next graphical session.
setup_user_units() {
    print_info "Installing session daemon units..."
    if bash "$SCRIPT_DIR/dotfiles-manager.sh" units; then
        print_success "Session daemon units installed and enabled"
    else
        print_warning "Could not install the units (no systemd user session?). Re-run: dotfiles-manager.sh units"
    fi
}

# Root-owned battery charge-cap timer (Dell charge_types). Needs sudo.
setup_battery_timer() {
    print_info "Installing the battery charge timer via dotfiles-manager.sh..."
    if ! bash "$SCRIPT_DIR/dotfiles-manager.sh" system --force; then
        print_warning "Battery timer install failed. Re-run: dotfiles-manager.sh system"
    fi
}

# True when a battery exposes the charge_types file the script writes.
has_charge_types() {
    compgen -G "/sys/class/power_supply/BAT*/charge_types" >/dev/null
}

# Initial system setup
system_setup() {
    print_info "Running initial system setup..."

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
    print_info "Generating initials avatar..."
    if ! command_exists python3; then
        print_warning "python3 not found, skipping avatar generation"
        return
    fi
    if ! python3 -c "from PIL import Image" 2>/dev/null; then
        print_warning "python3-pillow not found, skipping avatar generation"
        return
    fi

    bash "$CONFIG_DIR/scripts/generate-avatar.sh" &&
        print_success "Avatar installed to /var/lib/AccountsService/icons/$(whoami)" ||
        print_warning "Avatar generation failed"
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y | --yes) ASSUME_YES=true ;;
            -h | --help)
                sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
                exit 0
                ;;
            *)
                print_error "Unknown argument: $1"
                exit 2
                ;;
        esac
        shift
    done

    echo "========================================"
    echo "  Hyprland Dotfiles Setup"
    echo "========================================"
    echo ""

    # Check dependencies
    if ! check_dependencies; then
        if ask "Install missing dependencies? (y/N)" N; then
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

    # Session daemons as systemd user units
    echo ""
    if ask "Install and enable the session daemon units (battery, power, idle inhibitors)? (Y/n)" Y; then
        setup_user_units
    fi

    # Root-owned battery charge timer
    echo ""
    if [[ "$ASSUME_YES" == true ]] && ! has_charge_types; then
        print_info "No battery with charge_types found, skipping the battery charge timer"
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
        print_info "--yes: skipping Immich/Jellyfin setup (needs credentials); run setup.sh interactively for those"
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

# Run main function
main "$@"
