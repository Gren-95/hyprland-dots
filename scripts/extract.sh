#!/bin/bash
# extract.sh — unpack every archive in cwd (or given path).
#
# Handles: .zip .tar.gz .tar.bz2 .rar .7z
#
# Usage:
#   extract.sh           # extract in current directory
#   extract.sh <path>    # extract in <path>
set -uo pipefail

path="${1:-.}"
cd "$path" || exit 1

found=false

_extract() {
    local pattern=$1 exec=$2; shift 2
    local files=()
    shopt -s nullglob
    files=($pattern)
    shopt -u nullglob
    (( ${#files[@]} == 0 )) && return
    if ! command -v "$exec" >/dev/null; then
        echo "Warning: $exec is not installed. Cannot extract $pattern files."
        return
    fi
    for f in "${files[@]}"; do
        found=true
        echo "Extracting $f..."
        if "$@" "$f"; then
            echo "Successfully extracted $f"
        else
            echo "Error extracting $f"
        fi
    done
}

_extract '*.zip'     unzip unzip -o
_extract '*.tar.gz'  tar   tar -xzf
_extract '*.tar.bz2' tar   tar -xjf
_extract '*.rar'     unrar unrar x -o+
_extract '*.7z'      7z    7z x -o./

$found || echo "No archive files found in the specified directory."
