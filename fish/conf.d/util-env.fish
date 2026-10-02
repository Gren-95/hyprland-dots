# Load ~/.config/scripts/util.env into fish env (key=value lines).
# Lets abbrs/scripts reference $RPGMDECRYPT_PATH etc. without committing the
# values to git (util.env is gitignored). Secret-looking keys are skipped:
# scripts that need them (ledvance.sh) read util.env themselves.

set -l env_file $HOME/.config/scripts/util.env
test -f $env_file; or return 0

for line in (string split \n -- (string collect < $env_file))
    string match -qr '^\s*$|^\s*#' -- $line; and continue
    string match -q '*=*' -- $line; or continue
    set -l parts (string split -m1 = -- $line)
    string match -qri 'PASSWORD|SECRET|TOKEN' -- $parts[1]; and continue
    set -l value (string trim -c '"\'' -- $parts[2])
    set -gx $parts[1] $value
end
