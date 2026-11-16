#!/bin/bash
# ledvance.sh — pair a Tuya/Ledvance LED via the upstream pairing python.
#
# Reads credentials + script path from ~/.config/scripts/util.env:
#   LEDVANCE_USER=...
#   LEDVANCE_PASSWORD=...
#   LEDVANCE_PATH=/path/to/print-local-keys.py
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/env.sh"
load_util_env

: "${LEDVANCE_USER:?missing in util.env}"
: "${LEDVANCE_PASSWORD:?missing in util.env}"
: "${LEDVANCE_PATH:?missing in util.env}"

# The values reach Tcl through the environment, never through the script text:
# the command line is readable by every local user (ps, /proc/*/cmdline),
# while /proc/<pid>/environ is only readable by this user. It also keeps
# characters such as [ " $ in the password from being run as Tcl.
export LEDVANCE_USER LEDVANCE_PASSWORD LEDVANCE_PATH
# shellcheck disable=SC2016  # $env(...) is Tcl, expanded by expect
expect -c '
    spawn python $env(LEDVANCE_PATH)
    expect "Please put your Tuya/Ledvance username:"
    send -- "$env(LEDVANCE_USER)\r"
    expect "Please put your Tuya/Ledvance password:"
    send -- "$env(LEDVANCE_PASSWORD)\r"
    interact
'
