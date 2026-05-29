#!/usr/bin/env bash
# Stop and remove the Harbor deployment from Lab 6.

set -euo pipefail

WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$WORK_DIR"

if [[ -d harbor ]]; then
    cd harbor
    if [[ -f docker-compose.yml ]]; then
        echo "==> Stopping Harbor..."
        sudo docker compose down -v
    fi
    cd ..
    echo "==> Removing harbor/ directory..."
    sudo rm -rf harbor
else
    echo "No Harbor directory found; nothing to do."
fi

echo "==> Done."
