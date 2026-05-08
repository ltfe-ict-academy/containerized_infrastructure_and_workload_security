# Show the final Compose config after variable interpolation and merges.
docker compose config

# Build with fresh base image metadata.
docker build --pull -t myapp:secure .

# Generate a quick vulnerability overview if Docker Scout is available.
docker scout quickview myapp:secure

# List CVEs.
docker scout cves myapp:secure

# Generate SBOM.
docker scout sbom myapp:secure --output myapp.sbom.json

# Inspect effective container settings.
docker inspect <container_name>

# Check runtime processes and user.
docker compose exec app id
docker compose exec app ps aux

Use this as the acceptance rule: a normal web app container should usually run as non-root, with no added capabilities, no Docker socket, no privileged mode, read-only root filesystem, explicit tmpfs/volumes, resource limits, secrets as files, and only the minimum network/ports exposed.