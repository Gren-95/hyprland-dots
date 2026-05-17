#!/bin/bash
# ledvance.sh — pair a Tuya/Ledvance LED via the upstream pairing python.
#
# Reads credentials + script path from ~/.config/scripts/util.env:
#   LEDVANCE_USER=...
#   LEDVANCE_PASSWORD=...
#   LEDVANCE_PATH=/path/to/print-local-keys.py
set -uo pipefail

env_file="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/util.env"
if [[ -f "$env_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" != *=* ]] && continue
        key=${line%%=*}
        value=${line#*=}
        if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
            value=${BASH_REMATCH[1]}
        fi
        export "$key=$value"
    done < "$env_file"
fi

: "${LEDVANCE_USER:?missing in util.env}"
: "${LEDVANCE_PASSWORD:?missing in util.env}"
: "${LEDVANCE_PATH:?missing in util.env}"

expect -c "spawn python $LEDVANCE_PATH;\
expect \"Please put your Tuya/Ledvance username:\";\
send \"$LEDVANCE_USER\r\";\
expect \"Please put your Tuya/Ledvance password:\";\
send \"$LEDVANCE_PASSWORD\r\";\
interact"
