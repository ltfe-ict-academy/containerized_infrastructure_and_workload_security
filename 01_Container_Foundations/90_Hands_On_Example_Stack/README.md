# Hands-On Example Stack

This hands-on track is the practical backbone for Parts 01-04 of the course. We start with an intentionally simple and imperfect stack, then keep improving the exact same application throughout the week.

Day 1 is about getting a real containerized application running. We are not aiming for best practices yet. We want something concrete that participants can build, inspect, break, and later fix.

## What We Build In Part 01

We will build a small product catalog application with:

- a `frontend` container serving static HTML, CSS, and JavaScript
- a `backend` container exposing a simple Flask API
- a `postgres` database container storing products and demo users
- a `redis` container acting as a cache

At this stage the setup is intentionally minimal:

- broad images
- root inside the containers
- plain environment-variable secrets
- all service ports published to the host
- weak defaults that we will improve later

That is deliberate. We need a baseline before we can teach threat modeling, image hygiene, network segmentation, and hardening.

## Learning Goals

By the end of this hands-on section, participants should be able to:

- build a basic multi-container application with Docker Compose
- understand how the frontend, backend, database, and cache connect
- inspect containers, logs, networks, volumes, and environment variables
- recognize which shortcuts were acceptable for a Day 1 learning lab and which ones must be fixed later

## Folder Layout

```text
90_Hands_On_Example_Stack/
├── README.md
├── .env.example
├── compose.yaml
├── backend/
│   ├── app.py
│   ├── Dockerfile
│   └── requirements.txt
├── frontend/
│   ├── Dockerfile
│   ├── index.html
│   ├── app.js
│   └── styles.css
└── db/
    └── init/
        └── 01-schema.sql
```

## Architecture

```text
Browser
  |
  +--> frontend container  -> serves the UI on port 3000
  |
  +--> backend container   -> API on port 8000
          |
          +--> postgres     -> persistent data on port 5432
          |
          +--> redis        -> cache on port 6379
```

## Why This Version Is Intentionally Naive

This first version does many things that are not acceptable in production:

- uses wide base images
- copies more files than necessary into images
- runs services as root
- exposes PostgreSQL and Redis directly to the host
- stores secrets in plain text in environment variables
- includes an intentionally weak debug endpoint in the backend
- includes an intentionally unsafe SQL search route we will exploit and later fix

This is not an accident. These choices give us material for Part 02, Part 03, and Part 04.

## Prerequisites

- Docker Engine or Docker Desktop
- Docker Compose V2
- basic shell usage

## Step 1: Prepare The Environment File

Create a local `.env` from the example file.

Linux or macOS:

```bash
cp .env.example .env
```

PowerShell:

```powershell
Copy-Item .env.example .env
```

## Step 2: Build And Start The Stack

```bash
docker compose up --build
```

The first run downloads images, builds the frontend and backend containers, initializes PostgreSQL, and starts Redis.

## Step 3: Open The Application

- frontend: <http://localhost:3000>
- backend health: <http://localhost:8000/api/health>
- PostgreSQL: `localhost:5432`
- Redis: `localhost:6379`

## Step 4: Observe The Containers

In a second terminal:

```bash
docker compose ps
docker compose logs backend
docker compose logs db
docker compose logs redis
```

Important observations for Day 1:

- each service gets its own container
- Docker Compose creates a project-level network automatically
- the backend talks to `db` and `redis` by service name, not by hard-coded IP
- the PostgreSQL data survives container recreation because it uses a named volume

## Step 5: Explore The API

Get the health state:

```bash
curl http://localhost:8000/api/health
```

Fetch all products:

```bash
curl http://localhost:8000/api/products
```

Run a search:

```bash
curl "http://localhost:8000/api/products/search?q=red"
```

Clear the Redis cache:

```bash
curl -X POST http://localhost:8000/api/cache/clear
```

Inspect the intentionally weak debug route:

```bash
curl http://localhost:8000/api/admin/debug
```

That debug route is a teaching aid. It is not something we would keep in a real deployment.

## Step 6: Inspect The Running Environment

Check the Compose-created network:

```bash
docker network ls
docker network inspect 01_container_foundations_90_hands_on_example_stack_default
```

If your project name differs, use the name shown by `docker network ls`.

Inspect the backend container:

```bash
docker compose exec backend sh
```

Inside the container:

```sh
id
env | sort
python --version
```

What to notice:

- the process runs as root
- credentials are available as plain environment variables
- this is convenient for learning, but bad for real security

Inspect Redis from inside its container:

```bash
docker compose exec redis redis-cli PING
docker compose exec redis redis-cli KEYS '*'
```

Inspect PostgreSQL from inside the database container:

```bash
docker compose exec db psql -U postgres -d courseapp -c "SELECT id, name, price FROM products ORDER BY id;"
```

## Step 7: Understand The Application Flow

When the UI loads:

1. the browser loads static files from the `frontend` container
2. the frontend calls the backend API on port `8000`
3. the backend checks Redis for cached product data
4. if the cache is empty, the backend queries PostgreSQL
5. the backend stores the result in Redis and returns JSON to the UI

This gives us enough moving pieces to teach:

- container composition
- persistent storage
- service discovery
- caching
- logs
- process inspection
- later, image security and network segmentation

## Important Day 1 Shortcuts

These are acceptable for the first day because they help students move quickly, but they should trigger discussion:

### Wide Image Choices

The backend uses `python:3.12` and the frontend uses `nginx:latest`.

That is easy to understand, but it is not precise, minimal, or reproducible enough for production.

### Broad File Copies

Both Dockerfiles use broad copy patterns.

That is convenient at first, but it can leak files into images and make builds noisy.

### Direct Host Exposure

All four services publish ports to the host:

- frontend `3000`
- backend `8000`
- PostgreSQL `5432`
- Redis `6379`

This is useful for learning, but it is also a bad default. In later parts we will reduce exposure drastically.

### Plain Environment Secrets

PostgreSQL credentials and connection strings are passed through environment variables.

That is very common in early-stage demos and very common in incidents.

### Intentionally Unsafe Backend Routes

The backend includes:

- a debug route that reveals internal configuration
- a search endpoint built with unsafe string interpolation

We are keeping these on purpose because they will become practical attack material in Part 04.

## Exercise Ideas

1. Change one of the seeded products in `db/init/01-schema.sql`, remove the database volume, and recreate the stack.
2. Add a new product row to PostgreSQL and verify the frontend displays it after the cache is cleared.
3. Inspect `docker compose logs` for each service and identify which logs belong to the application, the database, and the cache.
4. Enter the backend container and confirm which environment variables it can read.

## Teardown

Stop the stack:

```bash
docker compose down
```

Stop the stack and remove the database volume as well:

```bash
docker compose down -v
```

Use `-v` only when you want to wipe the database and re-run the initialization scripts.

## What We Will Improve Later

Part 02:

- inspect the images
- scan them
- explain why the Day 1 builds are weak
- demonstrate breakout-style misconfiguration risks

Part 03:

- stop publishing unnecessary ports
- add a dedicated edge proxy
- segment the application into multiple networks
- add host firewall rules that work with Docker

Part 04:

- exploit the weak web app behavior
- harden runtime settings
- move secrets to files
- add monitoring, logs, and practical observability

This Part 01 stack is intentionally teachable before it is defensible.
