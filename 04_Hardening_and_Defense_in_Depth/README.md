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

## [Managing Secrets In Containerized Environments](./02_Managing_Secrets_in_Containerized_Environments/README.md)

## [Container Monitoring And Observability](./03_Container_Monitoring_and_Observability/README.md)
