# Hands On: Container Monitoring And Observability

Hardening makes a containerized application harder to compromise. Monitoring and observability help us notice when something is wrong, understand what changed, and reconstruct what happened during an incident. In a mature container environment, these two ideas belong together. A hardened service without visibility is quiet when it fails. An observable service without hardening is easy to study but still too easy to abuse.

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

## Files Added By This Hands-On Lab

The original application files are still present. The observability layer adds these files:

```text
docker-compose.observability.yaml
.env.observability.example
observability/
  alloy/config.alloy
  blackbox/blackbox.yml
  falco/rules/local_rules.yaml
  grafana/dashboards/container-operations.json
  grafana/dashboards/container-security-timeline.json
  grafana/provisioning/dashboards/dashboards.yml
  grafana/provisioning/datasources/datasources.yml
  loki/loki-config.yml
  prometheus/prometheus.yml
  prometheus/rules/container-security-rules.yml
  tempo/tempo.yml
scripts/generate-observability-events.sh
```

The overlay approach is important. It keeps the hardened application definition separate from the monitoring plane. In production, this also helps you apply different ownership, review, and access-control rules to application deployment files and observability deployment files.

## Requirements

Use a Linux Docker host when possible. Docker Desktop can run much of the stack, but Falco, cAdvisor, journald collection, and Beyla depend on host kernel visibility and may behave differently inside Docker Desktop's internal VM.

Recommended:

- Docker Engine with Docker Compose v2
- Linux kernel with eBPF support for Falco and Beyla
- systemd-journald if you want Docker daemon logs collected from the host journal
- at least 4 GB RAM available for the lab stack

The observability UI ports are bound to `127.0.0.1` by default. Keep that behavior for labs unless you intentionally place the host behind a VPN, firewall, or bastion.

## Start The Lab

From the extracted `example_app_final` directory:

```bash
cd example_app_final
```

For a local lab, use the local environment example:

```bash
cp .env.example .env
```

Create local secret files if they are not already present:

```bash
./scripts/create-local-secrets.sh
```

Start the hardened app plus the observability stack:

```bash
docker compose \
  -f docker-compose.yaml \
  -f docker-compose.observability.yaml \
  --profile beyla \
  up -d --build
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














While hardening limits the blast radius and secrets management secures the keys to the infrastructure, neither can thwart a sophisticated threat if defenders are blind to the activity within their cluster. Effective security requires the ability to answer critical questions during an incident: what is happening right now, which services are being abused, and where did the malicious traffic flow? This module explores monitoring and observability not just as tools for uptime, but as essential security telemetry. By establishing deep visibility into containerized environments, you empower defenders to detect the subtle shifts in behavior that distinguish a routine reliability issue from a targeted breach.

---
Runtime Detection and Incident Response
9.1 What Does Container Compromise Look Like?

Goal: Teach students what to observe after hardening.

Key topics
Suspicious processes
Unexpected network connections
New files in writable directories
Package installation at runtime
Reverse shells conceptually
Crypto-mining indicators
Container logs
Docker events
Host logs
Process monitoring
File integrity monitoring

MITRE ATT&CK’s Containers matrix is useful here because it frames container activity in terms of adversary tactics and techniques, including execution, persistence, privilege escalation, defense evasion, credential access, discovery, lateral movement, and escape-to-host scenarios.
---

## Observability concepts for Docker security
Topics
Monitoring vs observability vs logging vs detection
Why containers make visibility harder:
Short-lived processes
Dynamic names and IDs
Ephemeral filesystems
NAT and bridge networking
Shared host kernel
Volume mounts
Side effects of restart policies
Operational incidents vs security incidents
What defenders need to answer:
What changed?
Which container caused the spike?
Which image was running?
Was there unusual process, network, or file activity?
Did the container restart?
Did logs survive?
Can we reconstruct the timeline?

## Native Docker monitoring and troubleshooting
docker ps
docker inspect
docker stats
docker top
docker logs
docker events
docker system df
Docker daemon logs
Container lifecycle states:
Created
Running
Paused
Restarting
Exited
Dead
Healthy/unhealthy
Resource limits and what happens when containers exceed them
CPU throttling, memory limits, OOM kills, blocked I/O
PID counts and fork-bomb style behavior

## Container health checks and service readiness
Difference between:
Process running
Port open
Application healthy
Dependency ready
Service usable
Dockerfile HEALTHCHECK
Compose healthcheck
Health check intervals, timeouts, retries, and start periods
Common mistakes:
Health check only verifies that a process exists
Health check depends on external services
Health check is too expensive
Health check leaks credentials
Health check hides partial failure
Readiness patterns in Docker Compose
Using depends_on with health conditions

## Prometheus, cAdvisor, and Docker metrics
What metrics to collect from Docker hosts:
CPU
Memory
Network I/O
Block I/O
Filesystem usage
PID count
Restart count
Container count
Image/container age
Host saturation
Docker daemon metrics
cAdvisor
Node Exporter
Application metrics
Prometheus scrape model
Labels and cardinality
Metric naming
Pull vs push
Short-lived containers and scrape intervals
Why Docker daemon metrics, cAdvisor metrics, and application metrics are different

## Grafana dashboards for operations and security
Dashboard design principles
Difference between:
Executive dashboard
Operations dashboard
Security dashboard
Incident dashboard
Avoiding dashboard overload
Good panel types:
Time-series graphs
Stat panels
Tables
Logs panels
Heatmaps where useful
Container labels and dashboard variables
Dashboards by:
Host
Compose project
Service
Container
Image
Environment
Mapping dashboards to questions:
Is the service healthy?
Is the host saturated?
Which container changed?
What is consuming resources?
Did the issue begin after a deployment?
Is this operational or suspicious?


## Centralized container logging
Container stdout/stderr model
docker logs
Log rotation
Local logging drivers
Remote logging drivers
JSON logs
Structured logs
Correlation IDs
Log levels
Sensitive data in logs
Log retention
Log integrity
Log loss scenarios
Backpressure from logging systems
Difference between application logs, Docker daemon logs, and runtime/security logs

## OpenTelemetry and traces
Why infrastructure metrics are not enough
Application metrics:
Request count
Error count
Latency
Queue depth
Database query duration
Authentication failures
Distributed tracing basics
Trace/span model
OpenTelemetry Collector
OTLP
Receivers, processors, exporters
Service names and resource attributes
Correlation between logs, metrics, and traces
Sampling
Sensitive data risks in traces

The OpenTelemetry Collector receives traces, metrics, and logs, processes them, and forwards them to one or more observability backends through component pipelines. OpenTelemetry also defines semantic conventions to standardize names and attributes across telemetry data, which helps correlation across services and tools.

## Alerting and detection engineering
Alerting vs dashboarding
What makes an alert actionable?
Symptoms vs causes
Threshold alerts
Rate-of-change alerts
Absence alerts
Multi-window alerts
Alert fatigue
Alert severity
Routing and escalation
Runbook links
Silence and maintenance windows
Security alert examples:
New privileged container
Unexpected container created
Unhealthy production service
High outbound traffic
Container restart storm
Memory exhaustion
Suspicious runtime event

Prometheus alerting rules define alert conditions using Prometheus expressions and can use for durations to avoid firing immediately on transient conditions. Prometheus best-practice guidance also recommends keeping alerts simple, alerting on symptoms, and avoiding pages where there is nothing actionable to do.

## Docker events, daemon logs, and incident timelines
Docker daemon logs
Docker events stream
Container lifecycle event timeline
Image pulls
Container starts/stops/restarts
Health status changes
Network connect/disconnect events
Volume mount events
Limitations of native event history
Forwarding events to a durable backend
Building an incident timeline

## Runtime detection with Falco

Difference between metrics/logs and runtime security events
Syscall-based detection
Suspicious process execution
Shell spawned in container
Sensitive file reads
Writes below system directories
Package manager execution inside running container
Privilege escalation indicators
Container escape indicators
Docker socket access
Rule tuning
False positives
Sending runtime alerts to log/SIEM backends

## Compliance, audit evidence, and CIS Docker Benchmark
Why monitoring matters for compliance
CIS Docker Benchmark overview
What should be continuously monitored:
Docker daemon configuration
Socket exposure
Insecure registries
Privileged containers
Host PID/network namespace usage
Sensitive bind mounts
Containers running as root
Missing resource limits
Missing health checks
Logging configuration
Evidence collection
Continuous compliance vs point-in-time audit
Where observability supports audit findings

The CIS Docker Benchmark provides secure configuration guidelines for Docker, and CIS currently lists Docker Benchmark version 1.8.0 among recent available versions.


https://chatgpt.com/c/6a01a914-8b78-8325-a964-ba05d341a65a
---

## Security-Focused Use Cases

This is where the module becomes more than generic SRE content.

## Use Case 1: Web Exploit In Progress

Signals you may see:

- spike in suspicious request paths
- unusual 4xx/5xx mix
- child process execution from the web container
- outbound connections to new destinations
- read access to sensitive files

This is where:

- reverse proxy logs
- application logs
- traces
- Falco alerts

can tell a coherent story together.

## Use Case 2: Secret Theft Or Credential Abuse

Possible signals:

- sudden access to secret files
- unusual cloud API calls
- unexpected database connections
- audit-log events tied to an unusual container instance

Observability should make it easier to answer:

- which container read the credential?
- when?
- what did it do next?

## Use Case 3: Resource Exhaustion Or DoS

Possible signals:

- CPU saturation
- memory spikes
- request storms
- container restarts
- queue growth
- healthcheck failures

Without both application metrics and container metrics, teams often spend too long guessing whether the issue is code, traffic, or infrastructure.

## Use Case 4: Malicious Or Accidental Change

Possible signals:

- deployment event
- config change
- traffic pattern change
- new image digest
- alert spike immediately after rollout

This is why good observability always needs change context.

You do not want an incident timeline with everything except the actual rollout event.

## A Good Practical Incident Story

Use a simple example:

1. reverse proxy shows a spike in requests to an image-import endpoint
2. backend latency increases
3. traces show the request path reaching an outbound fetch routine
4. Falco flags an unexpected `sh` execution in the web container
5. logs show failed attempts to access internal metadata-style endpoints
6. container metrics show elevated outbound traffic

This is a much stronger teaching story than "logs are useful."

It shows how observability helps reconstruct an attack.

## Common Observability Mistakes

## 1. Logging Secrets

This is a security mistake and a compliance mistake.

## 2. High-Cardinality Label Abuse

Metrics become expensive and noisy when teams label with unbounded values such as:

- raw user IDs
- request IDs
- emails
- random paths

That hurts performance and destroys dashboard quality.

## 3. Only Monitoring The App

If you do not observe the host, the runtime, and change events, you miss too much context.

## 4. Only Monitoring Infrastructure

If you do not instrument the application, you miss the business logic and request context that explain incidents.

## 5. No Correlation Between Signals

If logs, metrics, and traces cannot be tied together, investigations become much slower.

## 6. No Retention Or Rotation Plan

A monitoring stack can become its own reliability incident if:

- logs fill the disk
- metrics retention is undefined
- alerts have no ownership

## 7. Alert Spam

A noisy alerting system teaches people to ignore the signal.

Alerts should be:

- actionable
- owned
- meaningful
- tied to clear runbooks where possible

## Practical Best Practices

1. Instrument the application, not just the host.
2. Collect logs, metrics, traces, and change events together.
3. Send application logs to `stdout` and `stderr` and centralize them.
4. Use structured logging and include request or trace correlation data.
5. Monitor both container and host resource usage.
6. Track image digests, deployments, and config changes as first-class observability events.
7. Add runtime security detections for suspicious process, file, and network behavior.
8. Rotate and retain logs intentionally so observability does not become a storage problem.
9. Avoid high-cardinality metric labels.
10. Make dashboards and alerts answer operational questions, not just look impressive.

## Good Discussion Prompts

- If one container in our stack were compromised, which signals would show it first?
- Do we currently have enough telemetry to reconstruct a web-to-container attack chain?
- Which of our current logs are useful, and which are just noise?
- Are we correlating deployments and image changes with production alerts?
- If we saw suspicious outbound traffic from one container, could we tell what request triggered it?

## Final Bridge To The Hands-On And Challenge

This module completes the Part 04 story.

At this point participants should understand:

- how web exploitation starts
- how hardening reduces blast radius
- how better secret handling reduces credential theft
- how telemetry helps defenders detect and investigate what still gets through

That is exactly the mindset they will need for the hardened hands-on environment and the final defensive challenge.

## Key Takeaways

- Monitoring tells you that something is wrong; observability helps you explain why.
- Containerized systems need telemetry from the app, the container runtime, the host, and the deployment pipeline.
- Logs, metrics, traces, and runtime detections each answer different questions.
- Security observability is strongest when it is integrated with ordinary operational telemetry.
- A blind environment is easy to exploit and hard to defend, no matter how well it was hardened on paper.

## References

- Docker logging overview: <https://docs.docker.com/engine/logging/>
- Docker local logging driver: <https://docs.docker.com/engine/logging/drivers/local/>
- OpenTelemetry overview: <https://opentelemetry.io/docs/what-is-opentelemetry/>
- OpenTelemetry documentation: <https://opentelemetry.io/docs/>
- OpenTelemetry Collector installation: <https://opentelemetry.io/docs/collector/installation/>
- Prometheus overview: <https://prometheus.io/docs/introduction/overview/>
- Prometheus metric types: <https://prometheus.io/docs/concepts/metric_types/>
- Grafana Loki documentation: <https://grafana.com/docs/loki/latest/>
- Grafana Alloy documentation: <https://grafana.com/docs/alloy/latest/>
- cAdvisor repository and documentation: <https://github.com/google/cadvisor>
- Falco documentation: <https://falco.org/docs/>
- Falco getting started: <https://falco.org/docs/getting-started/>
