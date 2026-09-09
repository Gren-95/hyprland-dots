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

    # ===== fzf =====
    # Colours from quickshell/Theme.qml. bg:-1 keeps the terminal's own
    # background so kitty's transparency still shows through. The behaviour
    # flags mirror what fzf.fish would otherwise set as its defaults - setting
    # this variable at all means the plugin stops supplying them.
    set -gx FZF_DEFAULT_OPTS "\
--cycle --layout=reverse --border --height=90% --preview-window=wrap --marker='*' \
--color=fg:#d6d3d1,fg+:#fafaf9,bg:-1,bg+:#332e2b \
--color=hl:#3b82f6,hl+:#60a5fa \
--color=info:#78716c,prompt:#3b82f6,pointer:#3b82f6 \
--color=marker:#22c55e,spinner:#a78bfa,header:#78716c \
--color=border:#3a3633,query:#fafaf9"

    # ===== Directory jumping =====
    # zoxide replaces the old `z` plugin. Guarded because this config syncs to
    # machines that may not have the binary installed yet.
    if type -q zoxide
        zoxide init fish | source
    end

    # Reload (full restart, not just source — clears stale state).
    alias reload 'exec fish'

end

# Outside is-interactive: scripts + non-interactive shells (Claude Code,
# editor terminals) inherit these.
set -gx PATH $HOME/.local/bin $HOME/bin $HOME/.nix-profile/bin ~/.npm-global/bin $PATH
set -gx RUSTC_WRAPPER sccache
