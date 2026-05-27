## Hands On: Containers Hardening & Secrets Management

This version starts from the already image-hardened and network-hardened application. The public entry point is still the reverse proxy, and the segmented Docker networks from the previous chapter remain in place. The new work is runtime hardening: how the containers are started, what privileges they receive, where they can write, how they consume secrets, and how Docker decides whether each service is healthy.

## Quick start

Create local secrets first:

```bash
chmod +x ./scripts/create-local-secrets.sh
./scripts/create-local-secrets.sh
```

Copy the `.env.example` file to `.env` and change any non-sensitive values if desired.

Then start the stack:

```bash
sudo docker compose up --build
```

Check service state:

```bash
sudo docker compose ps
```

Open the app through the reverse proxy:
```bash
http://<PUBLISH_HOST>:<PUBLIC_PORT>
```

Stop the stack when done:

```bash
sudo docker compose down -v
```

## What changed

### Secrets are no longer stored in `.env`

The starting example used `.env` values for the PostgreSQL and Redis passwords. That is convenient, but it is not a good place for secrets. Environment variables are easy to expose accidentally: they can appear in debug output, container inspection output, crash reports, stack traces, and careless logs. A `.env` file is also easy to copy, share, or commit by mistake.

We removed the real `.env` file from the final example and kept only `.env.example` with non-sensitive settings:

```env
COMPOSE_PROJECT_NAME=example_app_final
POSTGRES_DB=courseapp
POSTGRES_USER=courseapp
PUBLISH_HOST=127.0.0.1
PUBLIC_PORT=8080
```

The real passwords now live in files under `secrets/` and are mounted into the containers through Compose secrets:

```yaml
secrets:
  postgres_password:
    file: ./secrets/postgres_password.txt
  redis_password:
    file: ./secrets/redis_password.txt
```

Only the containers that need a secret receive it. The backend receives both passwords because it connects to PostgreSQL and Redis. PostgreSQL receives only the PostgreSQL password. Redis receives only the Redis password. The reverse proxy and frontend receive no secrets.

This is a small but important change. A compromised frontend or proxy container should not automatically contain database credentials just because the application stack has them somewhere.

### The backend reads secrets from files

The backend no longer receives a full `DATABASE_URL` or `REDIS_URL` containing passwords. Instead, it receives hostnames, ports, database names, and secret file paths:

```yaml
POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
REDIS_PASSWORD_FILE: /run/secrets/redis_password
```

The application reads those files at startup and builds the connection strings internally. This keeps password values out of the Compose environment section and out of the debug route. The debug route is still disabled, but even if it is enabled for a lab discussion, it now reports secret sources rather than secret values.

The backend health endpoint also changed. It now returns HTTP 503 when PostgreSQL or Redis is not reachable. A health endpoint that always returns 200 is useful only for checking whether the web framework is alive. In this example, the backend depends on the database and cache, so the health endpoint checks those dependencies too.

### PostgreSQL and Redis use secret files

PostgreSQL uses its `_FILE` environment variable convention:

```yaml
POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
```

Redis does not support the same password-file convention in the same way, so the Redis container reads the secret file during startup, writes a small temporary config file under `/tmp`, and starts `redis-server` with that generated config. The config file exists only inside the container's temporary filesystem. The password is not placed in the Compose file and is not passed as a long command-line argument.

This is not the same as a dedicated enterprise secret manager, but it is a better local Compose pattern than placing passwords directly in `.env` or in `docker-compose.yaml`.

### Containers run as non-root where the workload allows it

We explicitly set users for the application containers:

```yaml
user: "10001:10001"   # backend
user: "65532:65532"   # nginx-based containers
user: "999:999"       # Redis
```

The database container is left to its image entrypoint because PostgreSQL images often need to perform ownership and initialization work before dropping privileges internally. That exception is deliberate. Hardening should be strict, but it should also respect how the workload actually starts.

Running as a non-root UID does not make a compromised container harmless. It does change the attacker's starting point. Instead of immediately landing as UID 0 inside the container, the attacker lands as a constrained application user that should only be able to access the paths intentionally assigned to that service.

### New privileges are blocked

Every service uses:

```yaml
security_opt:
  - no-new-privileges:true
```

This prevents a process from gaining extra privileges through mechanisms such as setuid or setgid binaries. Running as a non-root user is good, but it is not enough if an image contains a helper binary that can elevate to effective root. `no-new-privileges` adds a runtime guardrail around that class of mistake.

### Capabilities are dropped

Most services use:

```yaml
cap_drop:
  - ALL
```

A normal web API, reverse proxy, static frontend, or cache service should not need kernel privileges such as mounting filesystems, changing routing tables, tracing other processes, loading kernel modules, or creating device nodes.

The PostgreSQL service has a small exception:

```yaml
cap_add:
  - CHOWN
  - DAC_OVERRIDE
  - FOWNER
  - SETGID
  - SETUID
```

Those capabilities are commonly needed by database entrypoints that initialize a data directory and then drop to a less-privileged database user. The important practice is not that every container must have exactly zero capabilities. The important practice is that capabilities are intentional. We start from `ALL` dropped and add back only the ones justified by the workload.

### The root filesystem is read-only

Every service uses:

```yaml
read_only: true
```

A running container should usually not need to modify the image filesystem. The image provides the application and its dependencies. Runtime state belongs in a database, a named volume, or a narrow temporary filesystem.

With a read-only root filesystem, an attacker who compromises the app has fewer places to drop tools, overwrite application code, modify startup files, or persist inside the container filesystem.

### Writable paths are explicit and temporary

Some services need temporary write space. Nginx needs places for temporary request files and a PID file. Redis needs a temporary config file. Python may need `/tmp` for temporary operations. Instead of leaving the whole container filesystem writable, we added explicit `tmpfs` mounts:

```yaml
tmpfs:
  - /tmp:size=64m,mode=1777
```

PostgreSQL also receives a temporary runtime socket directory:

```yaml
tmpfs:
  - /var/run/postgresql:size=16m,mode=1777
```

A `tmpfs` mount exists only for the lifetime of the container. It is useful for runtime scratch space, but it should not be used for data that must survive restarts. PostgreSQL data still uses a named Docker volume:

```yaml
volumes:
  - postgres_data:/var/lib/postgresql/data
```

### Resource limits were added

A container that has no extra privileges can still harm the host by consuming shared resources. We added limits for memory, swap, CPU, process count, file descriptors, restart loops, and logs.

Examples from the Compose file:

```yaml
mem_limit: 256m
memswap_limit: 256m
cpus: "1.00"
pids_limit: 200
ulimits:
  nofile:
    soft: 1024
    hard: 4096
restart: "on-failure:5"
logging:
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"
```

These values are intentionally modest because this is a lab application. In a real deployment, the right values come from measurement under normal and peak load. The point is that limits should be chosen deliberately. Leaving them unlimited because the correct number is not yet known is still a security decision, and usually not a good one.

### Docker's default seccomp and host security profiles stay enabled

We did not add `seccomp=unconfined`, `apparmor=unconfined`, `privileged: true`, host PID mode, host network mode, host devices, or Docker socket mounts.

That absence is part of the hardening. Container security is often weakened by runtime exceptions that were added to make an error disappear. In this example, the containers run with the default runtime isolation features instead of bypassing them.

### Health checks were added for every service

Health checks are not a monitoring stack. They are local readiness and liveness signals for the Compose environment. Monitoring and observability belong to a later chapter, but the runtime should still know whether a service is actually usable.

We used tools already present in each image instead of adding `curl` or `wget`:

- The reverse proxy and frontend use the `nginx` binary itself to validate configuration and check that the master process is alive.
- The backend uses `backend/healthcheck.py`, a small Python standard-library script that calls `http://127.0.0.1:8000/api/health` and verifies that the JSON status is `ok`.
- PostgreSQL uses `pg_isready`, which is already part of the PostgreSQL image.
- Redis uses `redis-cli`, which is already part of the Redis image, and reads the password from `/run/secrets/redis_password`.

The backend waits for healthy PostgreSQL and Redis. The reverse proxy waits for healthy frontend and backend. This prevents the proxy from being marked ready while the application behind it is still starting.

## Local Compose secrets caveat

For this lab, `scripts/create-local-secrets.sh` generates local files under `secrets/`. Those files are ignored by Git. They are created with permissions that keep the example runnable when containers are forced to run as non-root users.

This is appropriate for a local Compose lab, not for production secret storage. In production, prefer a real secrets management system or an orchestrator-backed mechanism that can control encryption, rotation, access policy, audit logs, and ownership more precisely. Examples include cloud secret managers, Vault-style systems, Kubernetes Secrets with encryption at rest, or the Secrets Store CSI Driver.

## Files changed or added

- `docker-compose.yaml` adds runtime hardening, resource limits, service health checks, and Compose secrets.
- `backend/app.py` reads database and Redis passwords from secret files and stops exposing connection URLs through debug output.
- `backend/healthcheck.py` adds a dependency-aware backend health check without adding curl.
- `backend/Dockerfile` copies the backend health check into the runtime image.
- `frontend/nginx.conf` makes the frontend Nginx container compatible with a read-only root filesystem.
- `frontend/Dockerfile` copies the frontend Nginx config.
- `proxy/nginx.conf` makes the reverse proxy compatible with a read-only root filesystem.
- `.env.example` now contains only non-sensitive configuration.
- `.gitignore` ignores real local secret files.
- `secrets/*.txt.example` documents the expected secret files without shipping real credentials.
- `scripts/create-local-secrets.sh` creates local lab secrets.
