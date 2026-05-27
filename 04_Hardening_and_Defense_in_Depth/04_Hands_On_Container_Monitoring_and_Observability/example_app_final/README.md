# Hands On: Container Monitoring And Observability

Hardening makes a containerized application harder to compromise. Monitoring and observability help us notice when something is wrong, understand what changed, and reconstruct what happened during an incident. In a mature container environment, these two ideas belong together. A hardened service without visibility is quiet when it fails. An observable service without hardening is easy to study but still too easy to abuse.

This lab adds a complete observability layer to the already hardened example application. The application code, Dockerfiles, secrets layout, and original `docker-compose.yaml` are left unchanged. The monitoring stack is added as a Compose overlay and an `observability/` directory so that the security controls from the previous hands-on section remain visible.

The goal is not only to show CPU charts. The goal is to build an operator and security view of the container environment:

- metrics from containers, the host, the Docker daemon, and HTTP probes
- centralized logs from every container
- Docker daemon logs from journald when the host supports systemd
- Docker lifecycle events, such as container starts, stops, restarts, exec sessions, and health changes
- runtime security findings from Falco
- traces through OpenTelemetry, Tempo, and optional zero-code eBPF instrumentation with Grafana Beyla
- Grafana dashboards for operations and incident timelines
- Dockhand as a container management UI, with Portainer available as an optional alternative

## Why Container Observability Is Different

A traditional application usually runs as a normal process on a server. A containerized application runs as a process too, but it is wrapped in extra layers: image, runtime, namespaces, cgroups, networks, volumes, secrets, health checks, restart policies, and daemon APIs. This means an investigation needs more than application logs.

When a backend becomes slow, the important question is not only, "what did the app log?" It is also:

- did the container restart?
- did it hit a memory limit?
- did the Docker daemon report health check failures?
- did someone run `docker exec` into the container?
- did Falco see a shell, suspicious file access, or unexpected process behavior?
- did the failure line up with a deployment, image pull, volume mount, or network change?
- did traces show that requests were stuck in the backend, database, Redis, or reverse proxy path?

Good container observability brings these answers into one place. In this lab, that place is Grafana.

## The Stack Used In This Lab

| Area | Tool | What it does in the lab | Security value |
| --- | --- | --- | --- |
| Dashboards and correlation | Grafana | Provides dashboards and Explore views for metrics, logs, and traces | Gives one place to pivot between an alert, a log line, a Docker event, and a trace |
| Metrics | Prometheus | Scrapes metrics from cAdvisor, node-exporter, Docker daemon metrics, Beyla, and blackbox probes | Detects resource pressure, restarts, health probe failures, and unusual container behavior |
| Container metrics | cAdvisor | Exposes per-container CPU, memory, filesystem, and network metrics | Shows whether a workload is resource constrained or behaving unusually |
| Host metrics | node-exporter | Exposes host CPU, memory, filesystem, network, and kernel-level metrics | Helps separate app failure from host failure |
| Docker daemon metrics | Docker Prometheus endpoint | Exposes Docker Engine metrics when enabled on the host | Adds runtime control-plane health to the dashboard |
| Centralized logs | Loki | Stores container logs, Falco output, Docker events, and Docker daemon logs | Provides fast incident timelines without running shell commands on every container |
| Telemetry collection | Grafana Alloy | Reads Docker container logs, reads journald, receives OTLP traces, and forwards telemetry | Replaces older agent patterns and keeps logs and traces in a single collector configuration |
| Runtime detection | Falco | Watches kernel events and applies runtime security rules | Turns behavior such as shell execution or sensitive file reads into searchable security alerts |
| Traces | Tempo | Stores distributed traces received through Alloy | Shows request paths and latency when traces are available |
| Zero-code app tracing | Grafana Beyla | Uses eBPF to observe HTTP traffic from the backend without changing the application | Gives baseline traces and RED metrics while keeping the app unchanged |
| Docker events | docker-events sidecar | Runs `docker events --format '{{json .}}'` and sends the stream into Loki through Docker logs | Creates a timeline of container lifecycle activity |
| Container UI | Dockhand | Provides a local UI for container inspection and management | Useful for labs and troubleshooting, but must be treated as sensitive because it uses the Docker socket |

There are many good tools in this space. Fluent Bit and Vector are excellent log shippers. Jaeger is widely used for tracing. Cilium Tetragon and Aqua Tracee are strong eBPF runtime detection options. For this hands-on section, the stack uses the Grafana LGTM family, Prometheus, cAdvisor, Falco, and Beyla because they fit well together in Docker Compose and make correlation easy for a small training environment.

## Architecture

The observability path is deliberately simple:

```text
Container stdout/stderr logs       -> Alloy -> Loki  -> Grafana
Docker events sidecar stdout       -> Alloy -> Loki  -> Grafana
Docker daemon journald logs        -> Alloy -> Loki  -> Grafana
Falco JSON stdout alerts           -> Alloy -> Loki  -> Grafana
cAdvisor / node-exporter / probes  -> Prometheus     -> Grafana
Docker daemon metrics              -> Prometheus     -> Grafana
Beyla RED metrics                  -> Prometheus     -> Grafana
Beyla or OTLP traces               -> Alloy -> Tempo -> Grafana
```

This is also how many real investigations work. A Prometheus alert tells us there is a symptom. Loki tells us what happened around that time. Docker events tell us what the runtime changed. Falco tells us whether behavior looked suspicious. Tempo tells us where request time was spent.

## Start The Lab

Presequisites:
```bash
# Create and edit the .env file
cp .env.example .env
# Create local secret files
chmod +x ./scripts/create-local-secrets.sh
./scripts/create-local-secrets.sh
# Create the observability environment file
cp .env.observability.example .env.observability
```

Start the hardened app:
```bash
sudo docker compose -f docker-compose.yaml up -d --build
sudo docker compose -f docker-compose.yaml logs -f
# Try if the app is working
```

Start the observability stack with the `beyla` profile:

```bash
sudo docker compose -f docker-compose.observability.yaml --profile beyla up -d
```

The `beyla` profile enables zero-code eBPF instrumentation of the backend container. When Beyla is not supported by the host kernel, remove `--profile beyla`; logs, metrics, Docker events, Falco, and synthetic traces will still work.

Open the main interfaces:

| Interface | URL | Default credentials |
| --- | --- | --- |
| Application | `http://127.0.0.1:8080` | none |
| Grafana | `http://127.0.0.1:3001` | `admin` / `course-observe-change-me` |
| Dockhand | `http://127.0.0.1:3002` | first-run setup depends on image version |
| Prometheus | `http://127.0.0.1:9090` | none |
| cAdvisor | `http://127.0.0.1:8081` | none |
| Loki | `http://127.0.0.1:3100` | API only |
| Tempo | `http://127.0.0.1:3200` | API only |

Grafana is pre-provisioned with Prometheus, Loki, and Tempo data sources. It also includes two dashboards:

- **Container Operations Overview**
- **Container Security Timeline**

Change the Grafana admin password before using this stack on a shared host.

## Optional: Enable Docker Daemon Metrics

Prometheus can scrape Docker daemon metrics, but Docker does not enable the Prometheus endpoint by default.

On a Linux Docker host, edit `/etc/docker/daemon.json`:

```json
{
  "metrics-addr": "127.0.0.1:9323"
}
```

Restart Docker:

```bash
sudo systemctl restart docker
```

The lab Prometheus container reaches the host as `host.docker.internal:9323`. On some Linux setups, binding Docker metrics to `127.0.0.1` is not reachable from a container. For a training VM, you can bind to the host bridge or to `0.0.0.0:9323`, but do that only with a firewall or isolated lab network. The Docker metrics endpoint should not be exposed to untrusted networks.

If Docker daemon metrics are not enabled, the `docker-daemon` Prometheus target will be down. The rest of the stack still works.

## What To Look At First

Open Grafana and start with the **Container Operations Overview** dashboard.

Look for:

- whether the application probes are passing
- CPU and memory usage per container
- recently restarted containers
- logs from `backend`, `frontend`, `reverse-proxy`, `db`, and `redis`
- whether the `beyla-backend` Prometheus target is up if the `beyla` profile is enabled

Then open **Container Security Timeline**.

This dashboard is designed for incident review. It puts Falco alerts, Docker events, Docker daemon logs, application probe failures, and suspicious log keywords in the same time window.

## Generate Useful Events

Run the helper script:

```bash
./scripts/generate-observability-events.sh
```

The script does five things:

1. sends normal HTTP requests through the reverse proxy
2. restarts the backend container to create Docker lifecycle events
3. runs a shell command inside the backend container to create Docker `exec` events and a Falco shell alert
4. reads `/etc/passwd` inside the backend container to generate a Falco file-read alert
5. sends synthetic OpenTelemetry traces through Alloy into Tempo

After the script finishes, go back to Grafana and set the time range to the last 15 minutes.

Useful Loki queries:

```logql
{compose_project="example_app_final"}
```

```logql
{service="falco"} | json
```

```logql
{service="docker-events"} | json
```

```logql
{service="docker-daemon"}
```

Useful Prometheus queries:

```promql
sum by (name) (rate(container_cpu_usage_seconds_total{name!="", image!=""}[5m]))
```

```promql
container_memory_working_set_bytes{name!="", image!=""}
```

```promql
probe_success
```

```promql
up{job="beyla-backend"}
```

If Beyla is running and the backend receives HTTP traffic, open Grafana Explore, select **Tempo**, and search recent traces. Beyla provides baseline transaction-level tracing without changing the backend source code. For deep internal spans, custom business attributes, and stronger trace-to-log correlation, application-level OpenTelemetry instrumentation is still the stronger production pattern.

## How The Security Timeline Works

The runtime security part of the lab relies on Falco. Falco watches kernel events and compares them with rules. This lab adds two simple local rules:

- `Training Shell Spawned In Container`
- `Training Sensitive File Read In Container`

These rules are intentionally easy to trigger and easy to read. They are not a complete production policy. They are here to show the flow:

```text
kernel activity -> Falco rule match -> JSON alert on stdout -> Docker log -> Alloy -> Loki -> Grafana
```

Docker events are collected separately:

```text
docker events --format '{{json .}}' -> docker-events container stdout -> Alloy -> Loki -> Grafana
```

That separation matters during incident response. A Falco alert says what suspicious behavior happened. Docker events say what the runtime was doing at the same time: container created, image pulled, service restarted, health status changed, or `exec` started.

## Operational And Security Best Practices

Keep observability private. Grafana, Prometheus, Loki, Tempo, cAdvisor, Dockhand, and Portainer are powerful operational interfaces. In this lab they bind to localhost by default. In production, put them behind SSO, network policy, TLS, and role-based access.

Treat the Docker socket as a high-risk control surface. Alloy, Dockhand, Portainer, Docker events, and Falco use the Docker socket or host visibility to inspect the environment. That visibility is useful, but it is also sensitive. Do not expose these services publicly, and do not run untrusted containers on the same host with access to observability credentials.

Collect enough data, but not everything forever. Metrics retention, log retention, and trace sampling should match the investigation window you need. This lab uses short local retention. Production systems usually send telemetry to durable storage with retention tiers.

Do not log secrets. Centralized logging makes investigation easier, but it also concentrates risk. Avoid printing tokens, database passwords, private keys, authorization headers, or full session cookies. Add redaction at the application, proxy, and collector layers.

Alert on behavior, not only availability. CPU and memory alerts are useful, but security teams also need alerts for shell execution, sensitive file access, image pulls from unexpected registries, Docker daemon reloads, repeated restarts, and unexpected `exec` sessions.

Pin and verify observability images. The lab uses image variables so students can run it easily. In a production baseline, pin versions or digests. Falco official images are signed and can be verified with `cosign`.

Monitor the monitoring stack. A stopped log collector, a down Prometheus target, or a broken Falco sensor is itself a security signal. The absence of telemetry should be visible.

## Troubleshooting

Check container status:

```bash
docker compose \
  -f docker-compose.yaml \
  -f docker-compose.observability.yaml \
  --profile beyla \
  ps
```

Check Grafana logs:

```bash
docker compose -f docker-compose.yaml -f docker-compose.observability.yaml logs -f grafana
```

Check Alloy logs:

```bash
docker compose -f docker-compose.yaml -f docker-compose.observability.yaml logs -f alloy
```

Check Falco logs:

```bash
docker compose -f docker-compose.yaml -f docker-compose.observability.yaml logs -f falco
```

If Falco fails on Ubuntu with AppArmor, the overlay already uses `apparmor:unconfined`, which is commonly needed for this kind of lab deployment. If the host exposes tracefs at `/sys/kernel/debug/tracing` instead of `/sys/kernel/tracing`, adjust the Falco volume in `docker-compose.observability.yaml`.

If Beyla does not produce traces, check that the host supports eBPF and BTF, that the backend is receiving HTTP traffic, and that the `beyla-backend` service is running with the `beyla` profile. Some language/framework combinations produce only baseline spans or may need application-level OpenTelemetry for detailed distributed tracing.

If Docker daemon logs are empty, the host may not use systemd-journald, the Docker unit name may be different, or the lab may be running inside Docker Desktop. Container logs and Docker events should still appear in Loki.

## Stop The Lab

Stop containers but keep data volumes:

```bash
docker compose \
  -f docker-compose.yaml \
  -f docker-compose.observability.yaml \
  --profile beyla \
  down
```

Remove observability and application data volumes as well:

```bash
docker compose \
  -f docker-compose.yaml \
  -f docker-compose.observability.yaml \
  --profile beyla \
  down -v
```

## References

- Grafana Alloy Docker log source: https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.docker/
- Grafana Alloy journald source: https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/
- Grafana Alloy and Tempo tracing: https://grafana.com/docs/tempo/latest/set-up-for-tracing/instrument-send/set-up-collector/grafana-alloy/
- Docker daemon Prometheus metrics: https://docs.docker.com/engine/daemon/prometheus/
- Docker events: https://docs.docker.com/reference/cli/docker/system/events/
- Falco container deployment: https://falco.org/docs/setup/container/
- Grafana Beyla: https://grafana.com/docs/beyla/latest/
- Grafana Beyla Docker setup: https://grafana.com/docs/beyla/latest/setup/docker/
- Grafana Beyla OpenTelemetry and Prometheus export: https://grafana.com/docs/beyla/latest/configure/export-data/
- Dockhand: https://github.com/fnsys/dockhand
- Portainer CE documentation: https://docs.portainer.io/
