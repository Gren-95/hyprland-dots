#!/bin/bash
# Toggle the WayVNC remote-access server, or manage its login.
# State is shown by the bar's remote-access status icon, so success sends no
# notification. The Services panel and Super+Ctrl+R both run this script.
#
# Usage:
#   wayvnc-toggle.sh            start wayvnc, or stop it when it is running
#   wayvnc-toggle.sh password   print the login (creates it on first use)
#   wayvnc-toggle.sh rotate     generate a new password
#
# Login: your login name plus a random password stored in ~/.config/wayvnc/password
# (gitignored, mode 600). Traffic uses a self-signed TLS certificate created on
# first use next to it. wayvnc/config holds only the bind settings; the
# password is merged into a temporary config in $XDG_RUNTIME_DIR for the start.
#
# wayvnc/config binds loopback. When Tailscale is up, the tailnet IPv4 address
# is passed on the command line instead, so the server is reachable over the
# tailnet only and never on the LAN.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/notify.sh"

PORT=5900
READY_TIMEOUT_DS=30 # deciseconds
CONF_DIR="$HOME/.config/wayvnc"
PASSWORD_FILE="$CONF_DIR/password"
TLS_KEY="$CONF_DIR/tls_key.pem"
TLS_CERT="$CONF_DIR/tls_cert.pem"
RSA_KEY="$CONF_DIR/rsa_key.pem"

new_password() {
    (umask 077 && openssl rand -base64 18 | tr -d '/+=\n' | head -c 20 >"$PASSWORD_FILE")
}

ensure_credentials() {
    [[ -s "$PASSWORD_FILE" ]] || new_password
    if [[ ! -s "$TLS_KEY" || ! -s "$TLS_CERT" ]]; then
        (umask 077 && openssl req -x509 -newkey rsa:3072 -nodes -days 3650 \
            -keyout "$TLS_KEY" -out "$TLS_CERT" -subj "/CN=$(hostname)" 2>/dev/null)
    fi
    if [[ ! -s "$RSA_KEY" ]]; then
        (umask 077 && openssl genrsa -traditional -out "$RSA_KEY" 3072 2>/dev/null)
    fi
}

case "${1:-toggle}" in
    password)
        ensure_credentials
        echo "user:     $(id -un)"
        echo "password: $(<"$PASSWORD_FILE")"
        exit 0
        ;;
    rotate)
        ensure_credentials
        new_password
        echo "New password: $(<"$PASSWORD_FILE")"
        echo "Restart remote access for it to take effect."
        exit 0
        ;;
    toggle) ;;
    *)
        echo "usage: wayvnc-toggle.sh [toggle|password|rotate]" >&2
        exit 2
        ;;
esac

if pgrep -x wayvnc >/dev/null; then
    pkill -x wayvnc || true
    exit 0
fi

ensure_credentials

# Runtime config = tracked bind settings + login. Lives on tmpfs, mode 600, and
# is removed as soon as wayvnc has read it.
runtime_conf="$XDG_RUNTIME_DIR/wayvnc-config"
(
    umask 077
    {
        cat "$CONF_DIR/config"
        echo "enable_auth=true"
        echo "username=$(id -un)"
        echo "password=$(<"$PASSWORD_FILE")"
        echo "private_key_file=$TLS_KEY"
        echo "certificate_file=$TLS_CERT"
        echo "rsa_private_key_file=$RSA_KEY"
    } >"$runtime_conf"
)
trap 'rm -f "$runtime_conf"' EXIT

# `tailscale ip` still prints the address while Tailscale is stopped, so ask the
# interface: the address is only bindable while tailscale0 actually holds it.
args=()
ts_ip=$(ip -4 -o addr show dev tailscale0 2>/dev/null | awk '{sub(/\/.*/, "", $4); print $4; exit}')
[[ -n "$ts_ip" ]] && args=("$ts_ip" "$PORT")

wayvnc --config "$runtime_conf" "${args[@]}" &>/dev/null &

# Readiness: wait until something listens on the port, or give up and say so.
for ((i = 0; i < READY_TIMEOUT_DS; i++)); do
    if ss -ltn "sport = :$PORT" | grep -q LISTEN; then
        exit 0
    fi
    sleep 0.1
done

pkill -x wayvnc || true
notify critical wayvnc dialog-error "Remote access" "wayvnc did not start listening on port $PORT" 5000
exit 1
