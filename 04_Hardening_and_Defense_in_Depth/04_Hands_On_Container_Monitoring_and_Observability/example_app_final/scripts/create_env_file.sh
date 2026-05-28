#!/usr/bin/env bash

set -euo pipefail
echo "Generating .env file with random credentials and server IP address..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_EXAMPLE="$ROOT_DIR/.env.example"
ENV_FILE="$ROOT_DIR/.env"

# ── Guard: refuse if .env already exists ────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE already exists. Cannot overwrite." >&2
    echo "Remove it manually first if you want to regenerate it." >&2
    exit 1
fi

# ── Resolve server IP from ens160 ────────────────────────────────────────────
SERVER_IP=$(ip -4 addr show ens160 2>/dev/null \
    | grep -oP '(?<=inet\s)\d+(\.\d+){3}' \
    | head -n 1)

if [[ -z "$SERVER_IP" ]]; then
    echo "ERROR: Could not read an IPv4 address from ens160." >&2
    echo "Check that the interface exists: ip addr show ens160" >&2
    exit 1
fi

# ── Generate random passwords ─────────────────────────────────────────────────
# openssl rand produces a fixed-length output so tr/head drain cleanly with no
# SIGPIPE, which would otherwise trip set -o pipefail and exit the script silently.
generate_password() {
    openssl rand -base64 48 | tr -d '/+=\n' | head -c 32
}

DOCKHAND_PASS=$(generate_password)
GRAFANA_PASS=$(generate_password)

# ── Write .env ────────────────────────────────────────────────────────────────
sed \
    -e "s|SERVER_IP_ADDRESS|$SERVER_IP|g" \
    -e "s|DOCKHAND_PASSWORD_PLACEHOLDER|$DOCKHAND_PASS|" \
    -e "s|GRAFANA_PASSWORD_PLACEHOLDER|$GRAFANA_PASS|" \
    "$ENV_EXAMPLE" > "$ENV_FILE"

chmod 600 "$ENV_FILE"

# ── Summary ───────────────────────────────────────────────────────────────────
echo "Created $ENV_FILE"
echo "  SERVER IP  : $SERVER_IP"
echo "  Dockhand   : $DOCKHAND_PASS"
echo "  Grafana    : $GRAFANA_PASS"
echo ""
echo "Store these credentials somewhere safe - they will not be shown again."
