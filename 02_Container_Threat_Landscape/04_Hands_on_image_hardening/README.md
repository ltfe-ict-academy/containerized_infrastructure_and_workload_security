# Hands-On Example Stack


- Use: https://docs.docker.com/build/building/best-practices/#dockerfile-instructions
- include the dockerfile best practices https://docs.docker.com/reference/dockerfile/#add
- https://github.com/ltfe-ict-academy/cloud-docker-kubernetes/tree/main/Part_06_Building_Images#understand-how-cmd-and-entrypoint-interact
- images that run as root by default, show USER in the Dockerfile
- smaller base image
- no `COPY . .`
- narrow build context via `Dockerfile.hardened.dockerignore`
- no `.env` in the build context
- no unnecessary shell tools or editors
- explicit non-root runtime user
-  Minimize The Runtime Image

### Step 4: Scan Both Images

```bash
trivy image --scanners vuln,secret,misconfig image-problem:insecure
trivy image --scanners vuln,secret,misconfig image-problem:hardened
```





Part 02 keeps the exact same application from Part 01, but now we stop treating it as "just a working demo". We treat it like an artifact that could be attacked, scanned, abused, and misused in practice.

This is the day where participants should start feeling uncomfortable with the Day 1 build.

We use two versions of the same stack:

- `compose.insecure.yaml` recreates the rough Day 1 build and adds controlled breakout-style demo services
- `compose.production.yaml` rebuilds the same app with safer image construction and operational handling

## Learning Goals

By the end of this hands-on section, participants should be able to:

- inspect insecure images instead of trusting them blindly
- explain why broad images, broad copies, mutable tags, and root processes matter
- show practical misconfiguration-based breakout paths
- compare insecure and hardened images using concrete evidence
- rebuild the same app with production-grade image practices without changing the business logic

## Folder Layout

```text
90_Hands_On_Example_Stack/
├── README.md
├── .env.example
├── compose.insecure.yaml
├── compose.production.yaml
├── backend/
│   ├── .dockerignore
│   ├── app.py
│   ├── Dockerfile
│   ├── Dockerfile.insecure
│   └── requirements.txt
├── frontend/
│   ├── .dockerignore
│   ├── app.js
│   ├── Dockerfile
│   ├── Dockerfile.insecure
│   ├── index.html
│   ├── nginx.conf
│   └── styles.css
└── db/
    └── init/
        └── 01-schema.sql
```

## Before You Start

This folder includes deliberate breakout demonstrations.

Do not run the escape demos:

- on your workstation
- on a shared Docker host
- on a production-like environment

Use a disposable lab VM only.

The goal is to teach reliable real-world breakout conditions caused by bad configuration, not to run unstable kernel-CVE party tricks.

## Step 1: Prepare The Environment File

Create `.env` from the example file.

Linux or macOS:

```bash
cp .env.example .env
```

PowerShell:

```powershell
Copy-Item .env.example .env
```

## Phase A: Explore The Insecure Build

### Step 2: Start The Insecure Stack

```bash
docker compose -f compose.insecure.yaml up --build -d
```

This produces local images named:

- `course-frontend:day2-insecure`
- `course-backend:day2-insecure`

### Step 3: Review The Running Services

```bash
docker compose -f compose.insecure.yaml ps
docker compose -f compose.insecure.yaml logs backend
docker compose -f compose.insecure.yaml logs frontend
```

The insecure version still exposes too much directly to the host:

- frontend `3000`
- backend `8000`
- PostgreSQL `5432`
- Redis `6379`

That is useful for analysis because it makes the weak assumptions highly visible.

### Step 4: Inspect The Images

```bash
docker image ls course-backend:day2-insecure course-frontend:day2-insecure
docker image history --no-trunc course-backend:day2-insecure
docker image history --no-trunc course-frontend:day2-insecure
docker image inspect course-backend:day2-insecure
docker image inspect course-frontend:day2-insecure
```

Things to call out during the lecture:

- the backend image is built from a broad Python base
- the frontend image uses `nginx:latest`
- both images are mutable-tag based
- the backend runs as root
- the frontend insecure build copies the entire folder into the static web root
- the backend still receives database credentials through environment variables

### Step 5: Look For Evidence Of Sloppy Build Context

Inside the insecure frontend container:

```bash
docker run --rm course-frontend:day2-insecure ls -la /usr/share/nginx/html
```

Inside the insecure backend container:

```bash
docker run --rm course-backend:day2-insecure sh -c "id && env | sort"
```

What to notice:

- build-time and source files can land in the runtime image
- the process runs as root
- connection details are easy to extract from the container environment

### Step 6: Scan The Insecure Images

With Trivy:

```bash
trivy image course-backend:day2-insecure
trivy image course-frontend:day2-insecure
```

Useful follow-up:

```bash
trivy image --scanners vuln,secret,misconfig course-backend:day2-insecure
```

This is a good place to reinforce an important habit:

- scanner output is evidence
- scanner output is not truth

Participants should inspect the build and the runtime assumptions, not just the CVE list.

### Step 7: Explore The App-Level Problems We Still Have

The backend is the same app from Part 01, which means it still includes:

- a debug endpoint
- unsafe SQL query construction in the search route
- plain-text connection strings in environment variables

Try them again:

```bash
curl http://localhost:8000/api/admin/debug
curl "http://localhost:8000/api/products/search?q=red"
```

These are not image problems by themselves, but they show how weak images and weak applications often travel together.

## Phase B: Demonstrate Reliable Breakout Misconfigurations

The escape services are not started by default. They are attached to the `escape` profile.

### Demo 1: Docker Socket Breakout

Start the socket-backed helper container:

```bash
docker compose -f compose.insecure.yaml --profile escape up -d socket-breakout
```

Now use the Docker socket from inside the container:

```bash
docker compose -f compose.insecure.yaml exec socket-breakout docker ps
```

That already proves the point:

- if a container can control the Docker daemon socket, it can usually control the host

To make the impact concrete:

```bash
docker compose -f compose.insecure.yaml exec socket-breakout \
  docker run --rm -v /:/host alpine:3.21 chroot /host sh -c "id && hostname && ls /"
```

Why this matters:

- mounting `/var/run/docker.sock` is effectively host control
- many teams do this for "convenience"
- this is one of the most common self-inflicted breakout patterns in real environments

### Demo 2: Privileged Host-Filesystem Breakout

Start the privileged host-mount lab service:

```bash
docker compose -f compose.insecure.yaml --profile escape up -d host-breakout
```

Enter it:

```bash
docker compose -f compose.insecure.yaml exec host-breakout sh
```

Inside the container:

```sh
chroot /host sh
id
hostname
```

Why this matters:

- `privileged: true`
- host root filesystem mounts
- host PID namespace sharing

is not "a little unsafe"

It is direct host compromise territory.

These demos are intentionally configuration-driven because they are reliable, teach the right lesson, and do not depend on whether a specific kernel escape CVE happens to work on the lab machine.

## Phase C: Rebuild The Same App Properly

### Step 8: Stop The Insecure Stack

```bash
docker compose -f compose.insecure.yaml down
```

### Step 9: Build The Production-Grade Image Set

```bash
docker compose -f compose.production.yaml build --pull
docker compose -f compose.production.yaml up -d
```

This produces:

- `course-frontend:day2-prod`
- `course-backend:day2-prod`

### Step 10: Compare The New Images

```bash
docker image ls course-backend:day2-insecure course-backend:day2-prod
docker image ls course-frontend:day2-insecure course-frontend:day2-prod
docker image history --no-trunc course-backend:day2-prod
docker image history --no-trunc course-frontend:day2-prod
```

Key improvements in the production-grade rebuild:

- narrower base images
- pinned major-version tags instead of `latest`
- multi-stage backend build
- a dedicated `.dockerignore`
- no broad `COPY . .` in the final images
- explicit runtime user for the backend image
- gunicorn instead of Flask development server
- frontend served through a minimal custom Nginx configuration
- database and Redis are no longer published to the host

### Step 11: Scan The New Images Again

```bash
trivy image course-backend:day2-prod
trivy image course-frontend:day2-prod
```

Discuss the difference carefully:

- fewer findings is useful
- smaller images are useful
- better layering is useful
- but we still have not solved network segmentation, runtime hardening, or secret management yet

That is why the rest of the course still matters.

## What Changed Technically

### Backend Image

The backend now:

- builds dependencies into a virtual environment in a builder stage
- copies only the runtime pieces into the final stage
- runs as a non-root user
- serves with gunicorn

### Frontend Image

The frontend now:

- stops using `nginx:latest`
- copies only the static assets it actually needs
- serves them on port `8080` via a minimal Nginx config

### Compose Handling

The production compose file now:

- uses health checks
- waits for dependencies to become healthy
- avoids publishing PostgreSQL and Redis
- uses explicit image tags so participants can inspect them directly

## Concepts To Reinforce During The Lab

- a working image can still be a dangerous image
- mutable tags are convenient but weak for identity
- running as root expands post-compromise options
- the Docker socket is a privilege boundary, not a convenience file
- privileged containers and host mounts are often functionally equivalent to host access
- production-grade image handling starts before runtime hardening begins

## Suggested Exercises

1. Use `docker image save` on the insecure backend image and inspect the resulting tarball.
2. Compare the `docker image history` output of the insecure and production backend images line by line.
3. Remove the `.dockerignore` file from the hardened build and observe what changes in the image content and build context.
4. Explain why the production image is better even though the backend application code itself is still not fully hardened.

## Teardown

Stop the production stack:

```bash
docker compose -f compose.production.yaml down
```

Stop the insecure stack and clean its volume:

```bash
docker compose -f compose.insecure.yaml down -v
```

## What We Still Haven't Solved

Part 03 will focus on:

- network segmentation
- a dedicated edge proxy
- better host exposure patterns
- Docker-aware host firewall rules

Part 04 will focus on:

- exploiting the weak web behavior still present in the app
- runtime hardening
- secrets handling
- observability and monitoring

After Part 02, participants should understand a crucial lesson:

image security is not a packaging detail

it is part of the attack surface.
