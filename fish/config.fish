if status is-interactive

    # Fish greeter
    set fish_greeting ""

    alias util="python3 $HOME/Documents/Code/linux-sysutil/cli_tool.py"

    # Basic dnf commands
    alias upi='echo "Updating system... Commands run: backup, up, fup, are, fare, fishup"; backup; and up; and fup; and are; and fare; and fishup'
    alias up="sudo dnf update"
    alias in="sudo dnf install"
    alias are="sudo dnf autoremove"
    alias re="sudo dnf remove"
    alias dls="sudo dnf list"

    # Basic Flatpak commands
    alias fup="flatpak update"
    alias fin="flatpak install"
    alias fare="flatpak remove --unused"
    alias fre="flatpak remove"

    # Basic Fisher commands
    alias fishup="fisher update"

    # System actions
    alias sdn="shutdown now"

    # Utils
    ## Networking
    alias ipa="util net ip"
    alias st="util net st"

    # Random
    alias nf="fastfetch"
    alias cls="clear"
    alias backup="util system backup"

    # File operations
    alias mvup="util file mvup"
    alias reload="fish -c 'source ~/.config/fish/config.fish'"

    set -gx PATH $HOME/.local/bin $HOME/bin $HOME/.nix-profile/bin $PATH

end
