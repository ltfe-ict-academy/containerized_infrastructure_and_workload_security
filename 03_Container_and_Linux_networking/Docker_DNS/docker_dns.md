# Chapter 6: Docker DNS and Service Discovery

## Theory

Docker DNS is a security topic because service discovery is also target discovery. Containers on custom Docker networks use Docker’s embedded DNS server, commonly visible as `127.0.0.11` inside `/etc/resolv.conf`. Docker Compose typically creates a default project network, and services can resolve each other by service name. This is operationally convenient because applications can connect to `db`, `redis`, or `api` instead of hard-coded IP addresses.

The attacker benefits from the same convenience. A compromised frontend container can try common names such as `db`, `postgres`, `redis`, `adminer`, `grafana`, `prometheus`, `minio`, and `api`. If the network is flat, those names may resolve and the services may be reachable. DNS aliases can make this even easier, because generic aliases such as `db` and `cache` are predictable. DNS is network-scoped, so proper segmentation reduces both discoverability and reachability.

DNS also matters for egress. Even when HTTP or HTTPS is restricted, DNS is often allowed. Attackers can use DNS for command-and-control lookups, environment discovery, or covert exfiltration. Defenders should log DNS queries, prevent direct arbitrary external DNS, and verify that VPN containers do not leak DNS outside the tunnel.

**Mechanism:** Docker's embedded DNS answers queries based on network membership. A container can resolve names for services attached to the same user-defined network, and Compose automatically registers service names and aliases inside the project networks it creates. Docker DNS improves application portability because containers can use stable names instead of changing IP addresses.

**Security consequence:** the same mechanism becomes an internal map for an attacker. A flat Compose network makes names like `db`, `redis`, `api`, and `adminer` easy to guess and often easy to reach. Segmentation reduces both DNS visibility and network reachability because names are scoped to the networks where the container participates.

## Red-Team Practical: Enumerate Service Names on a Flat Compose Network

Create `compose-flat.yml`.

```bash
cat > compose-flat.yml <<'YAML'
services:
  web:
    image: nicolaka/netshoot
    command: sleep infinity

  api:
    image: nicolaka/netshoot
    command:
      - sh
      - -c
      - |
        while true; do
          printf 'HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\napi' | nc -l -p 80
        done

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: insecure

  redis:
    image: redis:7-alpine

  adminer:
    image: adminer
YAML
```

Start the stack.

```bash
docker compose -f compose-flat.yml up -d
```

Enter the `web` container as if it were compromised.

```bash
docker compose -f compose-flat.yml exec web sh
```

Inside.

```sh
cat /etc/resolv.conf

for h in api db redis adminer postgres mysql mongo grafana prometheus minio backend cache; do
  echo "[*] resolving $h"
  getent hosts "$h" || true
done

nc -vz api 80
nc -vz db 5432
nc -vz redis 6379
curl -I http://adminer:8080
exit
```

Observation: common service names such as `api`, `db`, `redis`, and `adminer` resolve and are reachable from the compromised `web` container on the flat network.

Attacker perspective: Compose service names become a map of the application when networks are flat.

## Blue-Team Practical: Segment DNS Scope with Networks

Create `compose-segmented.yml`.

```bash
cat > compose-segmented.yml <<'YAML'
services:
  web:
    image: nicolaka/netshoot
    command: sleep infinity
    networks:
      - frontend

  api:
    image: nicolaka/netshoot
    command:
      - sh
      - -c
      - |
        while true; do
          printf 'HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\napi' | nc -l -p 80
        done
    networks:
      - frontend
      - backend

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: insecure
    networks:
      - backend

  redis:
    image: redis:7-alpine
    networks:
      - backend

  adminer:
    image: adminer
    networks:
      - backend

networks:
  frontend:
  backend:
    internal: true
YAML
```

Start the segmented stack.

```bash
docker compose -f compose-segmented.yml up -d
```

From `web`.

```bash
docker compose -f compose-segmented.yml exec web sh
```

Inside.

```sh
getent hosts api
getent hosts db || true
getent hosts redis || true
getent hosts adminer || true

nc -vz api 80
nc -vz db 5432 || true
nc -vz redis 6379 || true
curl -I --max-time 3 http://adminer:8080 || true
exit
```

From `api`.

```bash
docker compose -f compose-segmented.yml exec api sh
```

Inside.

```sh
getent hosts db
getent hosts redis
nc -vz db 5432
nc -vz redis 6379
exit
```

Observation: `web` resolves and reaches `api`, but does not resolve or reach `db`, `redis`, or `adminer`. `api` reaches backend services because it is intentionally attached to both networks.

Defensive interpretation: segmentation changes DNS discovery and reachability. The `api` service is now a deliberate bridge between frontend and backend, which is good architecture but also makes the API a high-value pivot if compromised.

## Red-Team Practical: Pivot from the Multi-Network API

The previous test proves that `web` cannot directly discover or reach backend services. The harder question is what happens if the explicitly multi-network service is compromised.

Inspect the API container's network memberships.

```bash
docker compose -f compose-segmented.yml ps
docker compose -f compose-segmented.yml exec api ip addr
docker compose -f compose-segmented.yml exec api ip route
cat compose-segmented.yml
```

From the compromised `web` container, confirm that backend names are outside its DNS scope.

```bash
docker compose -f compose-segmented.yml exec web sh -c '
  for h in db redis adminer; do
    echo "[web] $h"
    getent hosts "$h" || true
    nc -vz -w 2 "$h" 5432 2>/dev/null || true
    nc -vz -w 2 "$h" 6379 2>/dev/null || true
  done'

docker compose -f compose-segmented.yml exec web sh -c \
  'curl -I --max-time 3 http://adminer:8080 || true'
```

Now treat `api` as the compromised workload.

```bash
docker compose -f compose-segmented.yml exec api sh -c '
  for h in db redis adminer; do
    echo "[api] resolving $h"
    getent hosts "$h" || true
  done

  nc -vz db 5432
  nc -vz redis 6379
  curl -I --max-time 3 http://adminer:8080 || true'
```

Observation: `web` is blocked from backend discovery and reachability, but `api` resolves and reaches backend services because it is attached to both `frontend` and `backend`.

Attacker perspective: segmentation reduces the first compromised container's options, but a compromised bridge service can still pivot across every network it joins.

Defensive interpretation: multi-network services deserve special scrutiny. They should have the smallest possible runtime permissions, strong authentication to backend services, egress controls where practical, high-quality telemetry, and a clear owner because they are intentional trust-zone bridges.

Cleanup.

```bash
docker compose -f compose-flat.yml down
docker compose -f compose-segmented.yml down
```

---
