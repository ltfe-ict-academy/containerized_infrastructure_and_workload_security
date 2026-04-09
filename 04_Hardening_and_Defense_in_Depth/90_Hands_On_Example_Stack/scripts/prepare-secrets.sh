#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "${ROOT_DIR}/secrets/runtime"

for file in postgres_password app_db_password redis_password grafana_admin_password; do
  cp -n "${ROOT_DIR}/secrets/examples/${file}.txt" "${ROOT_DIR}/secrets/runtime/${file}.txt"
done

echo "Prepared training secrets in secrets/runtime/"
