# Defend The Flag: Harden A Self-Hosted Plane Deployment

## Scenario

You are given a Linux VM with a public IP address. Your task is to deploy a hardened [self-hosted Plane instance](https://github.com/makeplane/plane) using Docker Compose.

Plane is a multi-container project management platform. The starting deployment contains a public reverse proxy, web frontend services, an API service, background workers, a live service, PostgreSQL, Valkey/Redis, RabbitMQ, MinIO, and persistent Docker volumes. This makes it a realistic target for container hardening because a compromise of one service should not automatically expose the database, object storage, message broker, Docker host, observability stack, or administrative interfaces.

Your goal is not only to make Plane run. Your goal is to make Plane run with clear security boundaries, minimal public exposure, hardened containers, protected secrets, and useful monitoring.

## Target state

At the end of the challenge:

* The main Plane web interface is reachable over HTTPS from the public internet.
* The Plane API is reachable only where the application requires it, normally through the same HTTPS reverse proxy path or domain.
* No database, cache, message queue, object storage console, metrics endpoint, logging endpoint, Docker API, or admin dashboard is exposed directly to the public internet.
* Administrative access is available only through a private VPN path using Tailscale or WireGuard.
* Grafana, Prometheus, cAdvisor, Node Exporter, logs, and other observability tools are reachable only through the VPN.
* The Docker host is hardened.
* The Compose deployment uses least privilege wherever possible.
* Secrets are not committed to Git and are not casually exposed through container environment variables, logs, or image layers.
* The deployment includes evidence that the hardening was actually applied.

## Allowed public exposure

The public IP must expose only the minimum required services.

Required public ports:

* `80/tcp`: allowed only for HTTP-to-HTTPS redirect and certificate issuance.
* `443/tcp`: allowed for the Plane web interface and required API routes.

Optional during setup only:

* `22/tcp`: SSH may be temporarily exposed during bootstrap, but the final deployment should restrict SSH to the VPN interface or to a tightly scoped instructor-approved source IP range.

Not allowed publicly:

* PostgreSQL
* Redis or Valkey
* RabbitMQ management UI
* MinIO API or console
* Prometheus
* Grafana
* cAdvisor
* Node Exporter
* Loki, Promtail, Vector, or other log tooling
* Docker socket or Docker TCP API
* Any debug, development, or hot-reload service
* Any container management UI unless it is VPN-only and separately authenticated

## Required deliverables

Submit the following files and evidence:

1. `README.md`

   * Deployment overview
   * Threat model summary
   * Network diagram or service table
   * Public vs VPN-only access list
   * Hardening decisions
   * Known limitations

2. Hardened Compose files

   * `compose.yml`
   * `compose.override.yml`, `compose.prod.yml`, or similar if used
   * Monitoring Compose file if separated
   * VPN Compose file or host-based VPN setup notes

3. Configuration examples

   * `.env.example` with no real secrets
   * Reverse proxy configuration
   * Prometheus scrape configuration
   * Grafana provisioning files if used
   * Logging configuration if used

4. Security evidence

   * Output of public port scan
   * Output of local listening sockets
   * Output of `docker compose ps`
   * Selected `docker inspect` evidence showing hardened runtime settings
   * Image scan results
   * Screenshot or export of Grafana dashboard
   * Short test report explaining what is public, what is private, and what is blocked

5. Operational evidence

   * Backup script or documented backup procedure
   * Restore notes
   * Upgrade notes
   * Incident response notes for a suspected container compromise

## Phase 1: Baseline deployment

Start by deploying Plane in a clean and repeatable way.

Checklist:

* [ ] Clone or download the official Plane deployment files.
* [ ] Pin the Plane release or Git commit used for the challenge.
* [ ] Record the original services, exposed ports, networks, volumes, and environment variables.
* [ ] Bring the baseline stack up once and verify that the application works.
* [ ] Create an initial architecture table with each service and its purpose.

Example service table:

| Service       | Purpose            |               Public? | Persistent data? | Notes                               |
| ------------- | ------------------ | --------------------: | ---------------: | ----------------------------------- |
| proxy         | Public entry point |                   Yes |               No | Should be the only public container |
| web           | Plane web UI       | No direct public port |               No | Reached through proxy               |
| api           | Backend API        | No direct public port |               No | Reached through proxy               |
| worker        | Background jobs    |                    No |               No | Needs internal access only          |
| beat-worker   | Scheduled jobs     |                    No |               No | Needs internal access only          |
| live          | Real-time service  | No direct public port |               No | Reached through proxy if required   |
| plane-db      | PostgreSQL         |                    No |              Yes | Internal only                       |
| plane-redis   | Valkey/Redis       |                    No |     Yes/optional | Internal only                       |
| plane-mq      | RabbitMQ           |                    No |              Yes | Internal only                       |
| plane-minio   | Object storage     |                    No |              Yes | Internal only                       |
| grafana       | Dashboards         |              VPN only |              Yes | No public port                      |
| prometheus    | Metrics database   |              VPN only |              Yes | No public port                      |
| cadvisor      | Container metrics  |              VPN only |               No | Scraped by Prometheus               |
| node-exporter | Host metrics       |              VPN only |               No | Scraped by Prometheus               |

## Phase 2: Host hardening

The VM is part of the challenge. Do not treat it as a neutral platform. If the host is weak, the containers are weak.

Checklist:

* [ ] Update the host OS and reboot if the kernel was updated.
* [ ] Create a non-root administrative user.
* [ ] Disable password-based SSH authentication.
* [ ] Use SSH keys only.
* [ ] Restrict SSH to VPN access or approved source IPs.
* [ ] Enable a host firewall.
* [ ] Allow only `80/tcp`, `443/tcp`, and the VPN port if using WireGuard directly.
* [ ] Block direct public access to all observability and admin ports.
* [ ] Ensure Docker is not listening on a public TCP socket.
* [ ] Limit membership in the `docker` group.
* [ ] Enable Docker rootless mode or user namespace remapping if compatible with the final design.
* [ ] Document any compatibility issue that prevents rootless Docker or user namespace remapping.
* [ ] Configure Docker log rotation.
* [ ] Configure time synchronization.
* [ ] Install only required host packages.

Suggested verification commands:

```bash
sudo ss -tulpn
sudo ufw status verbose || sudo nft list ruleset
docker info --format '{{json .SecurityOptions}}'
getent group docker
```

Final public scan requirement:

```bash
nmap -Pn -p- <PUBLIC_IP>
```

Expected final result: only `80/tcp` and `443/tcp` should be publicly reachable, unless the instructor explicitly allows a VPN port.

## Phase 3: Public edge and TLS

The reverse proxy is the public entry point. Everything else should sit behind it.

Checklist:

* [ ] Use a reverse proxy such as Caddy, Nginx, or Traefik.
* [ ] Terminate TLS at the reverse proxy.
* [ ] Redirect HTTP to HTTPS.
* [ ] Expose only the reverse proxy on public ports.
* [ ] Do not publish `api`, `web`, `admin`, `space`, `live`, `plane-db`, `plane-redis`, `plane-mq`, or `plane-minio` directly to the host.
* [ ] Add security headers where compatible.
* [ ] Set sane upload limits.
* [ ] Disable unused routes or admin interfaces where possible.
* [ ] Ensure the Plane web interface requires authentication.
* [ ] Disable open self-registration if the scenario does not require it.
* [ ] Protect any admin path with VPN-only access or an additional authentication layer.

Public traffic should look like this:

```text
Internet
  |
  |  HTTPS 443
  v
Reverse proxy
  |
  +--> Plane web/API/live routes as required
```

It should not look like this:

```text
Internet
  |
  +--> PostgreSQL
  +--> Redis
  +--> RabbitMQ
  +--> MinIO
  +--> Grafana
  +--> Prometheus
  +--> Docker socket
```

## Phase 4: VPN for administration and observability

Administrative access must not rely on public dashboards.

Choose one option:

### Option A: Tailscale

Use Tailscale for the admin path. The VM joins a tailnet, and students access SSH, Grafana, Prometheus, and other admin services through the Tailscale IP or MagicDNS name.

Checklist:

* [ ] Install Tailscale on the host or run the official Tailscale container.
* [ ] Authenticate the VM to the tailnet.
* [ ] Restrict SSH to the Tailscale interface where possible.
* [ ] Bind Grafana and other admin services to VPN-only addresses or do not publish them at all.
* [ ] Do not use Tailscale Funnel for Grafana, Prometheus, or admin tools.
* [ ] Document the VPN access path.

### Option B: WireGuard

Use WireGuard if the challenge should avoid a managed mesh VPN.

Checklist:

* [ ] Generate server and client keys.
* [ ] Open only the WireGuard UDP port publicly.
* [ ] Allow SSH and observability access only from the WireGuard subnet.
* [ ] Do not expose Grafana, Prometheus, Node Exporter, cAdvisor, RabbitMQ, or MinIO publicly.
* [ ] Document peer configuration and allowed IP ranges.
* [ ] Rotate or remove test peers after the challenge.

VPN-only services:

| Service                 | Access path                              |
| ----------------------- | ---------------------------------------- |
| SSH                     | VPN only                                 |
| Grafana                 | VPN only                                 |
| Prometheus              | VPN only                                 |
| cAdvisor                | Scraped internally only                  |
| Node Exporter           | Scraped internally only                  |
| RabbitMQ management     | Disabled or VPN only                     |
| MinIO console           | Disabled or VPN only                     |
| Container management UI | Avoided, or VPN only with authentication |

## Phase 5: Docker network segmentation

Plane has several different trust zones. The public proxy does not need the same access as the database, and the observability stack does not need to be reachable from the internet.

Suggested network zones:

```yaml
networks:
  edge:
    driver: bridge

  app:
    driver: bridge
    internal: true

  data:
    driver: bridge
    internal: true

  monitoring:
    driver: bridge
    internal: true

  admin:
    driver: bridge
    internal: true
```

Checklist:

* [ ] Put the reverse proxy on the `edge` network.
* [ ] Put Plane application services on the `app` network.
* [ ] Put PostgreSQL, Valkey/Redis, RabbitMQ, and MinIO on `data`.
* [ ] Put Prometheus, Grafana, cAdvisor, Node Exporter, Loki, or other observability services on `monitoring`.
* [ ] Do not attach every container to every network.
* [ ] Do not publish internal service ports to the host.
* [ ] Use `expose` for internal documentation if helpful, but avoid `ports` unless the service must be reachable from outside Docker.
* [ ] Make internal networks `internal: true` where the services do not need direct outbound internet access.
* [ ] Document any service that needs egress and why.

Expected direction of communication:

```text
proxy -> web/api/space/live
api -> database/cache/message queue/object storage
worker -> database/cache/message queue/object storage
beat-worker -> database/cache/message queue
prometheus -> metrics targets
grafana -> prometheus/log store
```

Unexpected direction of communication:

```text
database -> internet
redis -> internet
rabbitmq -> internet
minio -> internet
grafana -> public internet users
prometheus -> public internet users
web -> docker socket
api -> docker socket
```

## Phase 6: Container runtime hardening

Apply hardening service by service. Some services may need small exceptions, but exceptions must be documented.

Baseline hardening options:

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
read_only: true
init: true
pids_limit: 256
mem_limit: 512m
cpus: "0.50"
restart: unless-stopped
```

Writable paths should be explicit:

```yaml
tmpfs:
  - /tmp:size=64m,noexec,nosuid,nodev
  - /run:size=16m,noexec,nosuid,nodev
```

Checklist:

* [ ] No service uses `privileged: true`.
* [ ] No service uses `network_mode: host` unless there is a documented VPN-specific exception.
* [ ] No service uses `pid: host`.
* [ ] No service uses `ipc: host`.
* [ ] No service mounts `/var/run/docker.sock`.
* [ ] No service mounts `/`, `/etc`, `/proc`, `/sys`, `/dev`, `/boot`, `/root`, Docker data directories, or sensitive host paths.
* [ ] Containers run as non-root where the image supports it.
* [ ] `no-new-privileges:true` is applied where possible.
* [ ] Capabilities are dropped by default.
* [ ] Added capabilities are justified one by one.
* [ ] Root filesystems are read-only where possible.
* [ ] Required write locations are provided with named volumes or explicit `tmpfs`.
* [ ] Resource limits are set for memory, CPU, PIDs, and file descriptors.
* [ ] `init: true` is enabled for services that may leave zombie processes.
* [ ] Health checks are added for important services.
* [ ] Restart policies avoid uncontrolled restart storms.
* [ ] Container logs have size and file-count limits.

Example logging limit:

```yaml
logging:
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"
```

Suggested minimum runtime checks:

```bash
docker inspect <container> --format 'Privileged={{.HostConfig.Privileged}}'
docker inspect <container> --format 'ReadonlyRootfs={{.HostConfig.ReadonlyRootfs}}'
docker inspect <container> --format 'CapDrop={{.HostConfig.CapDrop}} CapAdd={{.HostConfig.CapAdd}}'
docker inspect <container> --format 'SecurityOpt={{.HostConfig.SecurityOpt}}'
docker inspect <container> --format 'User={{.Config.User}}'
```

## Phase 7: Image and supply-chain hardening

The final deployment should make image trust visible.

Checklist:

* [ ] Pin image versions instead of using `latest`.
* [ ] Pin external images by digest where practical.
* [ ] Build application images in a repeatable way.
* [ ] Use BuildKit.
* [ ] Do not pass secrets through `ARG` or `ENV` during build.
* [ ] Use a `.dockerignore` file to keep secrets, Git history, local files, and test artifacts out of build context.
* [ ] Generate an SBOM for locally built images.
* [ ] Scan images with Trivy, Grype, Docker Scout, or another scanner.
* [ ] Fix critical and high vulnerabilities where a fix is available.
* [ ] Document accepted findings and why they are accepted.
* [ ] Remove unnecessary debug tools from final images where possible.
* [ ] Do not install packages into running containers.

Suggested commands:

```bash
trivy image <image-name>
syft <image-name> -o table
docker history --no-trunc <image-name>
```

## Phase 8: Secrets management

The starting deployment may rely heavily on environment files. For the hardened version, sensitive values must be treated as secrets.

Checklist:

* [ ] No real secrets are committed to Git.
* [ ] `.env` is excluded from Git.
* [ ] `.env.example` contains placeholders only.
* [ ] Database, RabbitMQ, MinIO, SMTP, secret keys, signing keys, and tokens are rotated from defaults.
* [ ] Secret files are owned by root or the deployment user and are not world-readable.
* [ ] Docker Compose `secrets:` are used where the application supports file-based secrets.
* [ ] If a service does not support `_FILE` variables, document the limitation and reduce exposure.
* [ ] Secrets do not appear in image history.
* [ ] Secrets do not appear in container logs.
* [ ] Secrets do not appear in `docker inspect` unless there is a documented unavoidable limitation.
* [ ] Admin credentials are unique per deployment.

Example pattern:

```yaml
secrets:
  postgres_password:
    file: ./secrets/postgres_password.txt

services:
  plane-db:
    secrets:
      - postgres_password
```

If the application requires an environment variable, do not pretend the risk is gone. Document the exposure and compensate with stronger host access control, file permissions, shorter credential lifetime, and rotation.

## Phase 9: Persistent storage and backups

A secure deployment also needs recoverability.

Checklist:

* [ ] Use named volumes for PostgreSQL, RabbitMQ, Redis/Valkey if persistent, MinIO uploads, Prometheus, Grafana, and logs.
* [ ] Do not bind-mount broad host directories.
* [ ] Any required bind mount is read-only unless write access is required.
* [ ] Backup PostgreSQL.
* [ ] Backup MinIO uploads.
* [ ] Backup important configuration files.
* [ ] Test restore on a clean VM or separate Compose project.
* [ ] Store backups outside the application directory.
* [ ] Protect backup files with permissions and encryption if they leave the VM.
* [ ] Document retention.

Suggested backup targets:

```text
PostgreSQL data
MinIO uploads
RabbitMQ state if message durability matters
Plane configuration
Reverse proxy configuration
Grafana dashboards/provisioning
Prometheus alert rules
```

## Phase 10: Monitoring and observability

Deploy an observability stack, but do not expose it publicly.

Required components:

* Prometheus
* Grafana
* Node Exporter for host metrics
* cAdvisor for container metrics
* Centralized container logs using Loki and Promtail, Vector, Fluent Bit, or an equivalent tool

Required dashboard coverage:

* Host CPU, memory, disk, filesystem usage
* Host network traffic
* Docker container CPU and memory usage
* Container restarts
* Container OOM kills
* Container network traffic
* Disk growth for Docker volumes
* Reverse proxy request rate and error rate if available
* PostgreSQL availability
* Redis/Valkey availability
* RabbitMQ availability
* MinIO availability
* Plane API health

Checklist:

* [ ] Prometheus is not public.
* [ ] Grafana is not public.
* [ ] cAdvisor is not public.
* [ ] Node Exporter is not public.
* [ ] Metrics are reachable only from the monitoring network and VPN path.
* [ ] Grafana requires authentication.
* [ ] Default Grafana credentials are changed.
* [ ] Prometheus scrapes Node Exporter.
* [ ] Prometheus scrapes cAdvisor.
* [ ] Prometheus scrapes reverse proxy metrics if available.
* [ ] Logs from Plane containers are centralized.
* [ ] Logs from the reverse proxy are centralized.
* [ ] Docker daemon logs or system logs are reviewed or collected.
* [ ] Dashboards are provisioned or documented.
* [ ] At least three alerts are defined.

Suggested alerts:

* High host disk usage
* Container restart loop
* Container killed due to memory limit
* Public service down
* Database down
* Unusual 5xx rate from reverse proxy
* Unexpected public listening port

## Phase 11: Access control and application hardening

Plane must not become an open public workspace unless that is explicitly part of the scenario.

Checklist:

* [ ] Use HTTPS.
* [ ] Create a strong initial admin account.
* [ ] Disable or restrict open signup if not needed.
* [ ] Configure SMTP securely if email is required.
* [ ] Do not expose test users or default passwords.
* [ ] Review admin routes and protect them.
* [ ] Review upload size limits.
* [ ] Ensure object storage is not anonymously public unless the application requires it.
* [ ] Review CORS and allowed host settings.
* [ ] Review OAuth or SSO settings if enabled.
* [ ] Document how authentication is enforced for the public web interface and API.

## Phase 12: Validation tests

You must prove the deployment is hardened.

Required tests:

### Public exposure test

From outside the VM:

```bash
nmap -Pn -p- <PUBLIC_IP>
```

Expected:

```text
80/tcp open
443/tcp open
```

No other public ports should be open unless approved.

### HTTP behavior test

```bash
curl -I http://<DOMAIN>
curl -I https://<DOMAIN>
```

Expected:

* HTTP redirects to HTTPS.
* HTTPS returns the Plane application or login flow.
* Security headers are present where configured.

### Internal service exposure test

From outside the VM, these must fail:

```bash
nc -vz <PUBLIC_IP> 5432
nc -vz <PUBLIC_IP> 6379
nc -vz <PUBLIC_IP> 5672
nc -vz <PUBLIC_IP> 15672
nc -vz <PUBLIC_IP> 9000
nc -vz <PUBLIC_IP> 9001
nc -vz <PUBLIC_IP> 9090
nc -vz <PUBLIC_IP> 3000
nc -vz <PUBLIC_IP> 8080
nc -vz <PUBLIC_IP> 9100
```

### Container hardening evidence

For each major service, collect evidence for:

```bash
docker inspect <container> --format '{{json .HostConfig.SecurityOpt}}'
docker inspect <container> --format '{{json .HostConfig.CapDrop}}'
docker inspect <container> --format '{{.HostConfig.Privileged}}'
docker inspect <container> --format '{{.HostConfig.ReadonlyRootfs}}'
docker inspect <container> --format '{{.Config.User}}'
docker inspect <container> --format '{{json .HostConfig.Binds}}'
```

### Secret exposure test

```bash
docker inspect <container> --format '{{json .Config.Env}}'
docker logs <container> | grep -Ei 'password|secret|token|key'
docker history --no-trunc <image-name> | grep -Ei 'password|secret|token|key'
```

Document any unavoidable exposure and explain how it is reduced.

### Monitoring test

* Open Grafana through VPN.
* Show host metrics.
* Show container metrics.
* Show logs for at least the proxy and API.
* Stop a non-critical container and show that restart or alerting is visible.
* Fill a test volume or simulate disk pressure only if safe and approved.

## Scoring guide

| Area                                      | Points |
| ----------------------------------------- | -----: |
| Working Plane deployment over HTTPS       |     10 |
| Public exposure limited to required ports |     15 |
| VPN-only admin and observability access   |     15 |
| Docker runtime hardening                  |     20 |
| Network segmentation                      |     15 |
| Secrets handling                          |     15 |
| Image scanning and supply-chain evidence  |     10 |
| Host hardening                            |     10 |
| Monitoring and logging                    |     15 |
| Backup and restore plan                   |     10 |
| Documentation and evidence quality        |     15 |
| Total                                     |    150 |

Bonus points:

* [ ] Docker rootless mode or user namespace remapping works and is documented.
* [ ] Images are pinned by digest.
* [ ] SBOMs are generated.
* [ ] A restore test is completed successfully.
* [ ] Alerts are tested.
* [ ] A clear network diagram is included.
* [ ] A short incident response runbook is included.

## Final rule

A service is not considered hardened just because it works. A service is considered hardened when the team can explain what it is allowed to access, what it is not allowed to access, what credentials it has, what happens if it is compromised, and how the deployment would show signs of trouble.
