#!/usr/bin/env fish
# Apply the Stone preset to tide's universal variables.
#
# tide reads its colours from universal variables, so this only needs running
# once — but `fisher update` replaces tide's own files while leaving universal
# variables alone, so re-running after an update is harmless and idempotent.
#
#   fish ~/.config/fish/tide-stone/apply.fish

set -l preset (status dirname)/stone.fish

if not test -r $preset
    echo "apply.fish: cannot read $preset" >&2
    exit 1
end

set -l applied 0
for line in (string match -rv '^\s*(#|$)' <$preset)
    set -l pair (string split -m1 ' ' -- (string trim -- $line))
    if test (count $pair) -ne 2
        echo "apply.fish: skipping malformed line: $line" >&2
        continue
    end
    set -U $pair[1] $pair[2]
    set applied (math $applied + 1)
end

echo "Stone applied: $applied tide variables set"
