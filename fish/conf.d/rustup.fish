test -f "$HOME/.cargo/env.fish" && source "$HOME/.cargo/env.fish"

# env.fish only exists under rustup; with Fedora's packaged rust nothing above
# runs, so cargo-installed binaries need putting on PATH explicitly.
test -d "$HOME/.cargo/bin" && fish_add_path -g "$HOME/.cargo/bin"
