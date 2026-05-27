#!/usr/bin/env sh
set -eu

COMPOSE_FILES="-f docker-compose.yaml -f docker-compose.observability.yaml"
APP_URL="${APP_URL:-http://127.0.0.1:8080}"

echo "[1/5] Generating application access logs through the reverse proxy..."
for path in /healthz /api/health /api/products; do
  curl -fsS "$APP_URL$path" >/dev/null || true
  printf '  requested %s\n' "$path"
done

echo "[2/5] Restarting backend to create Docker lifecycle events..."
docker compose $COMPOSE_FILES restart backend >/dev/null

echo "[3/5] Executing a shell in the backend container to generate Docker exec events and Falco shell alerts..."
docker compose $COMPOSE_FILES exec -T backend sh -c 'id; uname -a >/tmp/observability-demo.txt' >/dev/null || true

echo "[4/5] Reading /etc/passwd inside the backend container to generate a Falco file-read alert..."
docker compose $COMPOSE_FILES exec -T backend sh -c 'cat /etc/passwd >/tmp/passwd-copy' >/dev/null || true

echo "[5/5] Sending a short synthetic trace stream to Tempo through Alloy..."
docker compose $COMPOSE_FILES --profile trace-test up trace-generator

echo "Done. Open Grafana and inspect the Container Security Timeline dashboard."
