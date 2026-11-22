# Cargo lives under XDG data instead of ~/.cargo (Rust itself comes from Fedora packages).
set -gx CARGO_HOME $HOME/.local/share/cargo
test -d $CARGO_HOME/bin; and fish_add_path -g $CARGO_HOME/bin
