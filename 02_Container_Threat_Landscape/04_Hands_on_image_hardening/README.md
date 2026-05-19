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

