#!/bin/bash
# env.sh — load scripts/util.env (KEY=VALUE lines) into the environment.
#
# Parsed line by line instead of sourced, so values containing shell
# metacharacters are taken literally.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/env.sh"
#   load_util_env

load_util_env() {
    local env_file line key value
    env_file="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../util.env"
    [[ -f "$env_file" ]] || return 0
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
}
