# Hands-On: Image Hardening

## 1. Run the Dockerfiles Linters

The original backend image worked, but it behaved like a development container. It copied the whole build context, used a broad Python base image, installed dependencies directly into the image with `pip`, ran as root by default, and started Uvicorn with `--reload`. That is convenient for local coding, but it makes a poor production image.

Run the starting linters:
```bash
# Move to the example folder if you are not already there.
cd ~/containerized_infrastructure_and_workload_security/02_Container_Threat_Landscape/04_Hands_on_image_hardening

# This script runs Hadolint and Checkov against starting Dockerfiles.
chmod +x ./tools/lint-starting-dockerfiles.sh
./tools/lint-starting-dockerfiles.sh || true
```

Do not treat the linter as the final authority. Linters catch important patterns, but they cannot fully understand your threat model.


## 2. Narrow the build context before changing Dockerfiles

The most important improvement is often not inside the Dockerfile. It is the build context. A broad context means the builder can accidentally receive source history, local virtual environments, test artifacts, `.env` files, private keys, logs, and editor state. Even if the Dockerfile does not copy those files today, a future `COPY . .` or `ADD . /app` can turn them into image contents.
- The final backend `.dockerignore` uses an allowlist.
- The final frontend `.dockerignore` does the same.

We do not rely on humans remembering not to copy secrets. The context prevents the files from reaching the build in the first place. Second, the allowlist makes future code review easier. When a new file is needed by the build, the pull request must explicitly add it to `.dockerignore`, which turns a hidden build-context change into a visible security review item.

Quick check:

```bash
# BuildKit prints the transferred build context size during build.
# The final context should be much smaller than a repository-root build.
sudo docker buildx build --no-cache --progress=plain -t context-check ./example_app_final/backend
sudo docker buildx build --no-cache --progress=plain -t context-check ./example_app_final/frontend
```

## 3. Pin base images by tag and digest

Tags are convenient names. Digests identify content. A tag such as `python:3.12`, `postgres:18`, or `redis:8` can move over time. That may be desirable during development, but it is a weak production control because two hosts can pull the same tag at different times and receive different image contents.

The final Dockerfiles use tag-plus-digest references. The tag keeps the file readable, while the digest locks the exact image artifact.

Resolve image references to find the digests:
```bash
sudo docker buildx imagetools inspect dhi.io/python:3.14.5-debian13
sudo docker buildx imagetools inspect dhi.io/python:3.14.5-debian13-dev
sudo docker buildx imagetools inspect node:24-bookworm-slim
sudo docker buildx imagetools inspect dhi.io/nginx:1.31.0-debian13-fips
sudo docker buildx imagetools inspect dhi.io/postgres:18.4-alpine3.23-fips
sudo docker buildx imagetools inspect dhi.io/redis:8.6.3-debian13
```

## 4. Harden the backend image
- **Use a multi-stage backend build**: The starting backend installs everything directly into a full Python image. The hardened version separates the build stage from the runtime stage. The build stage may contain tools that are useful during build, such as `pip`, `uv`, package metadata, caches, and dependency resolution logic. The runtime stage receives only the virtual environment and the application file.
- **Move from `pip install` to `uv sync --locked`**: The final backend uses `uv` and a committed `uv.lock` file. This gives us a reproducible dependency set and a clear review point for Python dependency changes. The Dockerfile copies `pyproject.toml` and `uv.lock` before `app.py`, allowing dependency layers to be reused when only application code changes.
- **Copy only named files**: This removes accidental coupling between the host directory and the image. Adding a local `.env`, debug script, test database dump, or `.git` directory should not change the final runtime filesystem.
- **Use BuildKit cache mounts without baking caches into the image**: This keeps repeated builds fast without copying package caches into the runtime layer. Cache mounts belong to the builder. They are not part of the final image filesystem.
- **Use an explicit non-root runtime user**: Using a numeric user avoids needing to install `useradd`, `groupadd`, or shell tooling in the runtime image. We also use `COPY --chown` for the application file so the runtime user can read what it needs without requiring a runtime `chown` layer.
- **Remove development reload behavior**: The starting command used `--reload`. That makes sense during local development because Uvicorn watches files and restarts on changes. It does not belong in a hardened runtime image. The exec form avoids an unnecessary shell process and gives clearer signal behavior. The entrypoint is stable, while the default arguments remain easy to override in Compose or Kubernetes later.

## 5. Harden the frontend image
- **Use Node.js only as a builder**: The starter frontend image uses Node.js as the runtime image and starts the Vite development server. That ships npm, Node.js, package metadata, source files, and a development server into the running container. The final frontend uses Node.js only to build static assets. The runtime stage is Nginx and contains the generated `dist` directory only.
- **Use `npm ci`, not `npm install`**: `npm ci` is designed for locked, repeatable installs. It fails when the lockfile and `package.json` disagree. That failure is useful because dependency drift becomes visible. The `--ignore-scripts` option is deliberate. Many packages can execute lifecycle scripts during install. Sometimes scripts are legitimate, but they are also a supply-chain risk. For this frontend build, the selected dependencies build correctly without install scripts. If a future package requires scripts, that change should be reviewed explicitly.
- **Use build variables for non-sensitive frontend configuration**: This value is embedded into the built JavaScript bundle. That makes it appropriate only for non-sensitive configuration such as a public API path. It must not be used for tokens, passwords, or internal secrets.
- **Move to a hardened Nginx runtime image**: The final frontend image uses a hardened Nginx image and listens on a high port.

## 6. Harden public image references in Compose

For database and cache services, the original Compose file used public images from Docker Hub. The final Compose file uses hardened images from DHI's registry. That reduces the attack surface of the development environment and gives us more control over the image contents.

## 7. Build the final images and run the hardened application

Create a local `.env` file for the lab runtime only:
```bash
cp example_app_final/.env.example example_app_final/.env
```

Build the final images:
```bash
sudo docker buildx build --load --build-arg UV_VERSION=0.11.15   --build-arg UV_INDEX_URL="https://pypi.org/simple"   --build-arg APP_UID=10001 --build-arg APP_GID=10001   -t course/backend:final ./example_app_final/backend

sudo docker buildx build --load --build-arg VITE_API_BASE_URL="http://localhost:8000/api"  -t course/frontend:final ./example_app_final/frontend
```

Test the hardened application with Compose:
```bash
cd example_app_final
sudo docker compose up --build
# Stop with Ctrl+C, then:
sudo docker compose down -v
```