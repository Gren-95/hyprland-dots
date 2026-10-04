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

expect -c "spawn python $LEDVANCE_PATH;\
expect \"Please put your Tuya/Ledvance username:\";\
send \"$LEDVANCE_USER\r\";\
expect \"Please put your Tuya/Ledvance password:\";\
send \"$LEDVANCE_PASSWORD\r\";\
interact"
