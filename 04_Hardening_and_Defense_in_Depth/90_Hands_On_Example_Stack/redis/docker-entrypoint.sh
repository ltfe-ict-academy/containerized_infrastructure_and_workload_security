#!/usr/bin/env bash
set -euo pipefail

REDIS_PASSWORD="$(cat /run/secrets/redis_password)"

exec redis-server /usr/local/etc/redis/redis.conf --requirepass "${REDIS_PASSWORD}"
