#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_EXAMPLE" ]; then
  echo "Error: .env.example not found at $ENV_EXAMPLE"
  exit 1
fi

cp "$ENV_EXAMPLE" "$ENV_FILE"
echo "Created $ENV_FILE from $ENV_EXAMPLE"
