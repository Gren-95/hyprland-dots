if status is-interactive

    # Quiet greeter.
    set fish_greeting ""

    # ===== Abbreviations =====
    # Expand inline on <space> so you see the real command before running it
    # (better for screen-sharing, screencasts, and muscle memory). Complex
    # chains live in functions/ where abbr expansion doesn't apply.

    # DNF
    abbr -a up   sudo dnf update
    abbr -a in   sudo dnf install
    abbr -a are  sudo dnf autoremove
    abbr -a re   sudo dnf remove
    abbr -a dls  sudo dnf list

    # Flatpak
    abbr -a fup  flatpak update
    abbr -a fin  flatpak install
    abbr -a fare flatpak remove --unused
    abbr -a fre  flatpak remove

    # Fisher
    abbr -a fishup fisher update

    # System
    abbr -a sdn shutdown now

    # System shortcuts
    abbr -a backup sudo timeshift --create
    abbr -a st     speedtest-cli --simple
    abbr -a mstart mpv --no-video --shuffle ~/Music/*
    abbr -a mstop  pkill mpv
    abbr -a rpgmd  xdg-open \$RPGMDECRYPT_PATH
    # ipa, mvup live in functions/ (multi-token pipes don't read well inline)

    # Random
    abbr -a nf  fastfetch
    abbr -a cls clear

    # Reload (full restart, not just source — clears stale state).
    alias reload 'exec fish'

end

# Outside is-interactive: scripts + non-interactive shells (Claude Code,
# editor terminals) inherit these.
set -gx PATH $HOME/.local/bin $HOME/bin $HOME/.nix-profile/bin ~/.npm-global/bin $PATH
set -gx RUSTC_WRAPPER sccache
