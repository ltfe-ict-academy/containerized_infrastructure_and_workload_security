# Hands-On Example Stack





- ### Use host firewall rules carefully; Docker can add its own iptables / nftables rules.
- Use internal: true for networks that should not have external connectivity.
- Publish only required ports.
- Bind host ports to 127.0.0.1 when traffic should only be local or behind a reverse proxy.


Part 03 takes the cleaner images from Part 02 and fixes the next big problem: network design.

By Day 3 the stack should stop looking like "four containers with ports" and start looking like a service topology:

- one edge service exposed to the host
- one internal application network
- one internal data network
- explicit reverse proxy behavior
- explicit host firewall guidance that works with Docker

## Learning Goals

By the end of this hands-on section, participants should be able to:

- explain why `ports` and `expose` are not the same thing
- segment a Compose application into edge, app, and data networks
- front the stack with an Nginx reverse proxy
- stop publishing backend, database, and cache ports to the host
- apply host firewall controls in the correct place for Docker traffic

## Architecture

```text
Internet / Lab Client
        |
        v
  edge-proxy (published on host:8080)
        |
        +------------------ app_net (internal)
        |                     |
        |                     +--> frontend
        |                     +--> backend
        |
        +--> backend ---------- data_net (internal)
                                  |
                                  +--> postgres
                                  +--> redis
```

As of April 9, 2026, Docker still documents its nftables firewall backend as experimental, so this lab uses the stable iptables approach with rules in `DOCKER-USER`.

## Folder Layout

```text
90_Hands_On_Example_Stack/
|- README.md
|- .env.example
|- compose.yaml
|- backend/
|  |- app.py
|  |- Dockerfile
|  `- requirements.txt
|- frontend/
|  |- app.js
|  |- Dockerfile
|  |- index.html
|  |- nginx.conf
|  `- styles.css
|- edge/
|  |- Dockerfile
|  `- nginx.conf
|- host-firewall/
|  |- README.md
|  `- apply-docker-user-rules.sh
`- db/
   `- init/
      `- 01-schema.sql
```

## Step 1: Prepare The Environment File

Create `.env` from the example file if you do not already have one.

Linux or macOS:

```bash
cp .env.example .env
```

PowerShell:

```powershell
Copy-Item .env.example .env
```

## Step 2: Start The Segmented Stack

```bash
docker compose up --build -d
```

Published port summary:

- `8080` -> edge proxy

Nothing else should be published to the host.

## Step 3: Verify The Exposure Model

Check the running containers:

```bash
docker compose ps
```

Expected result:

- `edge-proxy` shows a published host port
- `frontend`, `backend`, `db`, and `redis` do not

Test the edge entrypoint:

```bash
curl http://localhost:8080/
curl http://localhost:8080/api/health
```

Try the old direct ports from Part 01 and Part 02:

```bash
curl http://localhost:8000/api/health
nc -zv localhost 5432
nc -zv localhost 6379
```

Those direct connections should fail because the backend, PostgreSQL, and Redis are no longer published to the host.

## Step 4: Inspect The Networks

List networks:

```bash
docker network ls
```

Inspect the three lab networks:

```bash
docker network inspect hands_on_networking_edge_net
docker network inspect hands_on_networking_app_net
docker network inspect hands_on_networking_data_net
```

What to verify:

- `edge-proxy` joins `edge_net` and `app_net`
- `frontend` joins only `app_net`
- `backend` joins `app_net` and `data_net`
- `db` joins only `data_net`
- `redis` joins only `data_net`

This is the core segmentation lesson:

- the browser reaches only the edge
- the edge can reach the app tier
- only the backend can reach the data tier

## Step 5: Test Service-to-Service Reachability

From the edge proxy:

```bash
docker compose exec edge-proxy wget -qO- http://frontend:8080/
docker compose exec edge-proxy wget -qO- http://backend:8000/api/health
```

From the backend:

```bash
docker compose exec backend python -c "import urllib.request; print(urllib.request.urlopen('http://frontend:8080').status)"
```

Now prove that the edge proxy cannot reach the database directly because it is not on the data network:

```bash
docker compose exec edge-proxy sh -c "wget -qO- http://db:5432 || true"
```

The request should fail.

## Step 6: Read The Proxy Configuration

The Nginx edge config does three important jobs:

- forwards `/` to the frontend service
- forwards `/api/` to the backend service
- preserves common proxy headers such as `Host`, `X-Real-IP`, and `X-Forwarded-For`

Key snippet:

```nginx
location /api/ {
    proxy_pass http://backend:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

This is where participants should understand that service names on user-defined networks are effectively the internal DNS names of the stack.

## Step 7: Understand The Network Best Practices We Applied

### Only One Host-Facing Service

The edge proxy is the only thing with published ports.

That means:

- fewer externally reachable services
- easier host firewall policy
- a single chokepoint for access logs, headers, request shaping, and later TLS

### Separate Internal Networks

We use three bridge networks:

- `edge_net` for host-facing traffic
- `app_net` for frontend and backend traffic
- `data_net` for PostgreSQL and Redis only

Both `app_net` and `data_net` are marked `internal: true`, which prevents direct external routing into them.

### No Database Or Cache Ports On The Host

This is one of the fastest wins in container security.

If PostgreSQL and Redis are not meant for host users, do not publish them.

### Health-Based Startup Dependencies

The edge does not start forwarding traffic until the backend is healthy, and the backend waits for the database and Redis to be healthy.

That improves reliability and removes a lot of noisy startup failure behavior.

## Step 8: Host Firewall Guidance

Open the firewall notes:

```bash
cat host-firewall/README.md
```

The included script does not replace understanding. It demonstrates the right control point:

- add filtering rules in the `DOCKER-USER` chain
- do not try to fight Docker by editing Docker-managed chains directly

Why this matters:

- Docker injects its own iptables rules when ports are published
- many generic host-firewall guides ignore that
- teams often think they blocked something while Docker is still forwarding it

The included script is intentionally conservative:

- allow the edge web port
- allow optional management access from a defined admin subnet
- drop direct access to ports that should never be reachable from outside

## Step 9: Apply The Firewall In A Lab VM

Only do this on a disposable Linux VM where you control console access.

```bash
sudo ./host-firewall/apply-docker-user-rules.sh eth0 8080 192.0.2.0/24
```

Adjust:

- network interface name
- published web port
- allowed management CIDR

Re-test:

```bash
curl http://localhost:8080/
```

Then verify that prohibited direct ports remain blocked.

## What This Part Fixes

- direct exposure of backend, PostgreSQL, and Redis
- flat single-network application topology
- lack of a dedicated ingress point
- firewall guidance that ignores Docker packet flow

## What This Part Does Not Fix Yet

- the backend still contains intentionally weak application behavior
- secrets are still handled too casually
- runtime hardening is still incomplete
- observability is still minimal

That is the Day 4 job.

## Suggested Exercises

1. Add a second frontend-only route in Nginx and verify it never reaches the backend.
2. Temporarily attach the edge proxy to the data network and explain why that is a bad idea.
3. Publish the backend port again, confirm it becomes reachable, then remove it and explain the difference between network attachment and host exposure.
4. Change the edge bind from `8080:8080` to `127.0.0.1:8080:8080` and discuss when localhost-only exposure is the right choice.

## Teardown

```bash
docker compose down
```

By the end of Part 03, the stack should feel much more deliberate:

- one entry point
- explicit internal paths
- clear trust boundaries
- firewall rules applied where Docker traffic actually flows
