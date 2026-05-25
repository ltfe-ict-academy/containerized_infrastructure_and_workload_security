# Hardening & Defense-in-Depth

## [Container Hardening Strategies](./01_Container_hardening_strategies/README.md)
- Keep the host OS, kernel, Docker Engine, Docker Compose, and container runtime updated
- Do not expose the Docker daemon over unauthenticated TCP
- Do not mount `/var/run/docker.sock` into application containers
- Restrict membership of the docker group; access to Docker is effectively privileged host access
- Strengthening Container Isolation with Seccomp
- Strengthening Container Isolation with AppArmor
- Strengthening Container Isolation with SELinux
- Other tips for strengthening container isolation
- Consider Docker rootless mode
- Don't use the `--privileged` flag
- Don't allow new privileges
- Set the right capabilities
- Do not mount sensitive host paths
- Add Resource Limits to Prevent Abuse and Denial of Service
- Run containers as a non-root UID/GID
- Run Periodic Security Benchmarks

## [Managing Secrets In Containerized Environments](./02_Managing_Secrets_in_Containerized_Environments/README.md)
- Secrets fundamentals and threat model
    - What is a secret?
    - Secret lifecycle
    - Threat model for containerized apps
- How secrets leak in Docker projects
    - Secrets in source code
    - Secrets in `.env` files committed to Git
    - Secrets in `docker-compose.yml`
    - Secrets in Dockerfile `ENV`
    - Secrets in Dockerfile `ARG`
    - Secrets in image layers
    - Secrets in `docker history`
    - Secrets in build cache
    - Secrets in logs
    - Secrets in crash dumps
    - Secrets in shell history
    - Secrets in CI/CD job output
    - Secrets in Docker inspection output
    - Secrets in mounted volumes
    - Secrets in container process environments
    - Secrets via `/var/run/docker.sock`
- Docker Compose secrets
- Build-time secrets with Docker BuildKit
- Secret storage options

## [Container Monitoring And Observability](./03_Container_Monitoring_and_Observability/README.md)
