# Hands-On Example Stack

Part 04 turns the same catalog application into a hardened single-node deployment with practical observability.

This part has two modes:

- `compose.attack.yaml` overlays intentionally weak settings onto the stack so participants can exploit the application in a controlled lab
- `compose.yaml` is the hardened default build with secrets files, runtime restrictions, TLS at the edge, and a working monitoring and logging path

## Learning Goals

By the end of this hands-on section, participants should be able to:

- exploit a weak web route and explain why the exploit worked
- see the difference between image hardening and runtime hardening
- move sensitive values from environment variables to files mounted as secrets
- apply practical container runtime restrictions
- stand up a single-node stack with metrics, logs, and a Grafana view into both





## Example: Harden a real Docker Compose app
Exercise

Participants review a sample application and classify each value as:

Secret
Sensitive but not a secret
Configuration
Public metadata
Unknown / requires policy decision


Hands-on lab

“Find the leaks” lab:

Inspect a vulnerable Docker project.
Search Git history for secrets.
Inspect image history.
Inspect runtime environment.
Review Compose files.
Review container logs.
Produce a short risk report.

Hands-on lab

Refactor a Compose app that currently uses:

environment:
  DB_PASSWORD: supersecret

into a safer design using:

.env.example
local-only ignored .env
Compose secrets for sensitive values
clear config/secret separation

Hands-on lab

Build a three-service application:

web
worker
db

Tasks:

Create separate secrets for database password, API token, and admin bootstrap password.
Grant each service only the secrets it needs.
Modify application code to read from /run/secrets.
Use _FILE style environment variables for images that support them.
Verify secrets are not present in the Compose file or image history.

Participants build an image that needs a private package token.

Bad version:

ARG NPM_TOKEN
RUN npm config set //registry.npmjs.org/:_authToken=$NPM_TOKEN

Secure version:

RUN --mount=type=secret,id=npm_token \
    NPM_TOKEN="$(cat /run/secrets/npm_token)" && \
    npm config set //registry.npmjs.org/:_authToken="$NPM_TOKEN" && \
    npm ci

Participants then inspect:

image history
final filesystem
build logs
cache behavior


Hands-on lab

Modify a small Python/Node/Go service to:

Read secrets from files.
Avoid printing secret values in logs.
Redact secrets in error output.
Fail safely if a secret is missing.
Support a restart-based rotation workflow.

Participants compare four designs for the same Docker Compose app:

Plain .env
Compose secrets from local files
Encrypted secrets in Git using SOPS
Runtime fetch from an external secret manager

They score each design against:

developer usability
production safety
auditability
rotation support
failure modes
operational complexity

Create a CI workflow that:

Builds a Docker image with BuildKit secrets.
Runs a secret scan.
Verifies no secret is present in the final image.
Publishes only if checks pass.
Uses environment-scoped secrets.

A production database password was committed to Git and used in a Docker Compose deployment.

Participants must decide:

Is this an incident?
What systems are affected?
What needs to be rotated?
What logs must be checked?
What containers must be restarted?
What evidence should be preserved?
What long-term controls should be added?

Capstone: harden a Docker Compose application

Learning objectives

Participants apply the whole course to a realistic project.

Scenario

A small company has a Docker Compose app with:

web service
background worker
PostgreSQL
Redis
private package dependency
third-party API token
CI pipeline
staging and production environments

The current project contains secrets in:

.env
docker-compose.yml
Dockerfile ARG
CI logs
image history
app logs

Capstone tasks

Participants must:

Create a secret inventory.
Remove hardcoded secrets.
Refactor runtime secrets into Docker Compose secrets.
Refactor build credentials into BuildKit secrets.
Add .env.example.
Add .gitignore and .dockerignore controls.
Add secret scanning.
Add CI/CD masking and protected variables.
Write a rotation runbook.
Write a short team policy.

Final deliverables

Hardened docker-compose.yml
Hardened Dockerfile
Secret inventory
Rotation runbook
CI/CD pipeline snippet
Risk assessment
Short presentation explaining trade-offs







## Final Architecture

```text
Browser
  |
  v
edge-proxy (HTTP -> HTTPS redirect, TLS termination)
  |
  +--> frontend
  +--> backend
          |
          +--> postgres
          +--> redis
          |
          +--> metrics exposed to Prometheus

Prometheus <-- backend metrics, cAdvisor
Grafana    <-- Prometheus + Loki
Alloy      <-- Docker logs -> Loki
```

## Folder Layout

```text
90_Hands_On_Example_Stack/
|- README.md
|- compose.yaml
|- compose.attack.yaml
|- .env.example
|- .gitignore
|- backend/
|- frontend/
|- edge/
|- redis/
|- db/
|- monitoring/
|  |- prometheus/
|  |- loki/
|  |- alloy/
|  `- grafana/
|- secrets/
|  |- examples/
|  `- runtime/
|- certs/
|  `- runtime/
`- scripts/
```

## Step 1: Prepare The Environment File

Linux or macOS:

```bash
cp .env.example .env
```

PowerShell:

```powershell
Copy-Item .env.example .env
```

## Step 2: Prepare The Training Secrets

Linux or macOS:

```bash
./scripts/prepare-secrets.sh
```

PowerShell:

```powershell
./scripts/prepare-secrets.ps1
```

These commands copy training-only values from `secrets/examples/` into `secrets/runtime/`.

Why we do it this way:

- participants get runnable files
- the runtime files are separated from the committed examples
- the Compose stack can mount secrets as files

## Step 3: Generate A Local TLS Certificate

Linux or macOS:

```bash
./scripts/generate-dev-cert.sh
```

PowerShell:

```powershell
./scripts/generate-dev-cert.ps1
```

This creates local training certificates in `certs/runtime/`.

The default host ports come from `.env`:

- HTTPS: `8443`
- HTTP redirect: `8080`
- Grafana: `3000` on localhost only
- Prometheus: `9090` on localhost only

## Phase A: Run The Attack Overlay

The attack overlay reintroduces a few intentionally weak behaviors:

- debug routes enabled
- unsafe SQL queries enabled
- direct backend port published on `127.0.0.1:18000`
- backend runtime restrictions relaxed so students can compare the difference

### Step 4: Start The Vulnerable Overlay

```bash
docker compose -f compose.yaml -f compose.attack.yaml up --build -d
```

### Step 5: Confirm The Debug Route Is Reachable

```bash
curl http://127.0.0.1:18000/api/admin/debug
```

What to observe:

- the route exists only because the overlay enabled it
- the app is willing to disclose operational information that should never be exposed in production

### Step 6: Exploit The Unsafe Search Query

Run a normal query first:

```bash
curl "http://127.0.0.1:18000/api/products/search?q=red"
```

Now run a training SQL injection payload:

```bash
curl "http://127.0.0.1:18000/api/products/search?q=' UNION SELECT id, username, password_hash, 0 FROM app_users -- "
```

Why this works:

- the vulnerable route interpolates user input directly into SQL
- PostgreSQL receives attacker-controlled query structure, not just attacker-controlled data

This is the point where participants should connect the web exploit to the surrounding container environment:

- the application is weak
- the backend container is now directly reachable
- runtime hardening is reduced
- the overall blast radius is larger than it should be

### Step 7: Stop The Attack Overlay

```bash
docker compose -f compose.yaml -f compose.attack.yaml down
```

## Phase B: Start The Hardened Single-Node Stack

### Step 8: Start The Hardened Default Stack

```bash
docker compose up --build -d
```

### Step 9: Access The Application Through The Edge

- HTTPS app: <https://localhost:8443>
- HTTP redirect entry: <http://localhost:8080>
- Grafana: <http://127.0.0.1:3000>
- Prometheus: <http://127.0.0.1:9090>

Expected behavior:

- HTTP redirects to HTTPS
- the backend is no longer published directly
- the debug route is disabled
- the search route uses safe parameterized queries

## Step 10: Verify The Hardening Choices

Check the running services:

```bash
docker compose ps
```

Inspect the backend environment:

```bash
docker compose exec backend env | sort
```

What to notice:

- the database password is no longer in the environment
- Redis credentials are not exposed as environment variables either

Test filesystem restrictions:

```bash
docker compose exec backend sh -c "touch /tmp/ok && touch /app/should-fail"
```

Expected result:

- writing to `/tmp` works because it is a tmpfs
- writing to `/app` fails because the container uses a read-only root filesystem

Check the runtime user:

```bash
docker compose exec backend id
docker compose exec edge-proxy id
docker compose exec frontend id
```

## Step 11: Verify The Application Behavior Changed

The hardened backend should reject the same attack route as data, not as SQL structure:

```bash
curl "https://localhost:8443/api/products/search?q=' UNION SELECT id, username, password_hash, 0 FROM app_users -- " -k
```

The results should reflect a safe query path instead of leaking rows from `app_users`.

The debug endpoint should now be disabled:

```bash
curl https://localhost:8443/api/admin/debug -k
```

## Step 12: Explore The Monitoring And Logging Stack

Prometheus scrapes:

- backend application metrics at `/metrics`
- container runtime metrics from cAdvisor

Alloy discovers Docker containers through the Docker socket and forwards their logs to Loki.

Grafana is pre-provisioned with:

- a Prometheus data source
- a Loki data source
- a simple dashboard for app requests, latency, and container resource use

Useful checks:

```bash
docker compose exec prometheus wget -qO- http://backend:8000/metrics | head
docker compose logs alloy
docker compose logs loki
```

In Grafana:

1. open the provisioned dashboard
2. generate a few product and search requests in the UI
3. watch request counters and latency move
4. open Explore and query logs by service label

## What We Hardened In Practice

### Secrets Handling

We now mount passwords as files and read them from:

- `/run/secrets/postgres_password`
- `/run/secrets/app_db_password`
- `/run/secrets/redis_password`
- `/run/secrets/grafana_admin_password`

That is a major improvement over plain environment-variable secrets.

### Runtime Controls

The hardened app-facing services use:

- non-root users
- `read_only: true`
- `tmpfs` mounts for writable scratch paths
- `cap_drop: [ALL]`
- `security_opt: ["no-new-privileges=true"]`
- `pids_limit`
- health checks

### Traffic Exposure

Only the edge proxy is host-facing.

Admin tools such as Grafana and Prometheus bind only to localhost by default.

### Observability

The stack now has a realistic minimum observability path:

- application metrics
- container metrics
- centralized container logs
- a dashboard and an explore workflow

## What This Final Lab Is And Is Not

This is a strong single-node training example. It is not a full production platform.

It gives participants a realistic end state for:

- one node
- one app stack
- one edge proxy
- secrets handling
- runtime restrictions
- monitoring and logging

It does not try to solve:

- multi-node orchestration
- distributed secret stores
- HA databases
- external certificate automation
- enterprise policy enforcement pipelines

Those are important topics, but they are beyond the scope of this week.

## Suggested Final Exercises

1. Add another backend endpoint and expose its metrics in Grafana.
2. Tighten the edge proxy further by blocking the debug path explicitly even if the backend enables it.
3. Move the HTTPS host port from `8443` to `443` and update the redirect behavior accordingly.
4. Extend the dashboard with a panel for cache hit behavior or search latency.
5. Write down which controls came from image security, which came from networking, and which came from runtime hardening.

## Teardown

```bash
docker compose down
```

If you want to remove data and metrics volumes as well:

```bash
docker compose down -v
```

By the end of Part 04, participants should see the full journey clearly:

- Day 1 built the app
- Day 2 cleaned up the images and exposed breakout mistakes
- Day 3 fixed the network shape
- Day 4 hardened the workload and made it observable
