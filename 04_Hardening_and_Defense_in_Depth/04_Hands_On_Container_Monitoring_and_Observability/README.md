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

## Presequisites

Before starting this lab, make sure you have:
```bash
# Move to the working directory
cd ~/containerized_infrastructure_and_workload_security/04_Hardening_and_Defense_in_Depth/04_Hands_On_Container_Monitoring_and_Observability/example_app_final

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

Create the observability network:
```bash
sudo docker network create observability_net
```

<!-- TODO: Write this better -->
Edit the `.env` in the observability directory


## Container inspection and management with Dockerhand

Tools such as Portainer and Dockhand provide a graphical control plane for container environments. They can make it easier to see containers, images, volumes, networks, stacks, logs, resource usage, and deployment state from one place. **[Portainer](https://www.portainer.io/)** supports Docker, Kubernetes, Docker Swarm, Podman, and ACI environments, and exposes management features through a GUI and API.

From a security perspective, these tools must be treated as administrative interfaces, not simple dashboards. A container management UI often has the ability to start containers, stop containers, open shells, view logs, edit stacks, change environment variables, and interact with images, volumes, and networks. That means it should be protected with strong authentication, least-privilege access, audit logging, regular updates, network restrictions, and preferably exposure only through a VPN, private admin network, or trusted reverse proxy.

**[Dockhand](https://dockhand.pro/)** is a modern Docker management application focused on real-time container management, Docker Compose stack orchestration, and multi-environment support. It includes features such as starting and stopping containers, visual Compose editing, Git-based stack deployment, remote Docker host management, terminal access, real-time logs, vulnerability scanning, and container activity tracking.

[Deployment security considerations](https://dockhand.pro/manual/#security-summary):
- Dockhand needs access to Docker to manage containers. By default, the Dockhand container runs as a non-root user, which may not have permission to access the socket on your host system.
- We placed a proxy between Dockhand and the actual Docker socket. This filters which API calls are allowed. A popular tool for this is [tecnativa/docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy).
- Always restrict access to Dockhand itself using a reverse proxy with authentication, VPN (Tailscale/WireGuard), SSO/OIDC, or network segmentation. Treat Dockhand as an admin interface that should never be directly exposed to the internet.

> The proxy acts as a firewall for the Docker API. It allows only necessary commands (list, start, stop containers) but can block dangerous ones (`docker run --privileged`, system commands). Dockhand connects to the proxy via a private Docker network, isolated from the raw socket. The socket proxy container itself requires elevated privileges to access the Docker socket, which transfers some security risk to the proxy container. Even with a socket proxy, anyone who gains access to Dockhand still has significant capabilities — starting/stopping containers, deleting volumes, pulling images, viewing logs, and more. The proxy limits the most dangerous operations but doesn't make Dockhand "safe to expose publicly".

Start deploying the observability services:
```bash
# Run Dockhand container
cat docker-compose.dockhand.yaml
sudo docker compose -f docker-compose.dockhand.yaml up -d
sudo docker compose -f docker-compose.dockhand.yaml logs -f

# Go to http://{PUBLIC_BIND_IP}:3003/ and log in with the credentials from the .env file.
```

After starting the stack, configure Dockhand to use the proxy:
- Go to Settings > Environments
- Add a new environment or edit the default one
- Set connection type to Direct
- Set the host to `socket-proxy:2375`
- Save the environment

To enable vulnerability scanning, follow the [instructions in the Dockhand documentation](https://dockhand.pro/manual/#images-scan).


## Run the observability stack

In the Prometheus config change the server IP under `static_configs`
<!-- # TODO  -->

To run the stack follow the instructions bellow:
```bash
# Check the docker-compose file
cat docker-compose.observability-stack.yaml

# Start the stack
sudo docker compose -f docker-compose.observability-stack.yaml up -d
# Check the logs
sudo docker compose -f docker-compose.observability-stack.yaml logs -f
```

## Run the Node exporter

Host metric monitoring is an essential part of maintaining reliable infrastructure, because it provides visibility into the health and performance of servers and virtual machines. By collecting metrics such as CPU usage, memory consumption, disk utilization, filesystem capacity, and network activity, teams can detect resource bottlenecks early, investigate performance issues faster, and prevent outages before they affect users. These metrics also help with capacity planning, alerting, and understanding how applications behave under different workloads.

[Prometheus Node Exporter](https://github.com/prometheus/node_exporter) is a widely used exporter for collecting host-level hardware and operating-system metrics from Linux and other Unix-like systems. It exposes system metrics in a Prometheus-compatible format, allowing Prometheus to scrape, store, query, and alert on them. With Node Exporter, teams can monitor key indicators such as CPU load, available memory, disk space, disk I/O, filesystem usage, and network traffic from a single monitoring pipeline. This makes it easier to build dashboards, define meaningful alerts, and maintain a clear view of infrastructure health across multiple hosts.

To run the stack follow the instructions bellow:
```bash
# Check the docker-compose file
cat docker-compose.node-exporter.yaml
# Start the node exporter
sudo docker compose -f docker-compose.node-exporter.yaml up -d
# Check the logs
sudo docker compose -f docker-compose.node-exporter.yaml logs -f
```

After starting the stack wait a few moments for the services to initialize, then open Grafana at `http://{PUBLIC_BIND_IP}:3001/` and check the `Node Exporter: Host Metrics` dashboard.

## Exporting container metrics with cAdvisor

[cAdvisor](https://github.com/google/cadvisor) (Container Advisor) provides container users an understanding of the resource usage and performance characteristics of their running containers. It is a running daemon that collects, aggregates, processes, and exports information about running containers. Specifically, for each container it keeps resource isolation parameters, historical resource usage, histograms of complete historical resource usage and network statistics. This data is exported by container and machine-wide.

cAdvisor has native support for Docker containers and should support just about any other container type out of the box.

To run the stack follow the instructions bellow:
```bash
# Check the docker-compose file
cat docker-compose.cadvisor.yaml
# Start cAdvisor
sudo docker compose -f docker-compose.cadvisor.yaml up -d
# Check the logs
sudo docker compose -f docker-compose.cadvisor.yaml logs -f
```

After starting the stack wait a few moments for the services to initialize, then open Grafana at `http://{PUBLIC_BIND_IP}:3001/` and check the `cAdvisor: Container Metrics` dashboard.

## Checking Services availability with Blackbox Exporter

[Prometheus Blackbox Exporter](https://github.com/prometheus/blackbox_exporter) is a monitoring component used to check whether services are reachable and behaving correctly from the outside. Unlike exporters that collect internal metrics from an application or host, Blackbox Exporter performs active probes against endpoints using protocols such as HTTP, HTTPS, DNS, TCP, ICMP, and gRPC. This makes it useful for monitoring service availability, response time, status codes, DNS resolution, TCP connectivity, TLS certificate validity, and whether an application is actually reachable from the network.

In a containerized application deployment, Blackbox Exporter can be used to monitor exposed services, APIs, ingress routes, load balancers, internal service endpoints, and external dependencies. For example, in a Docker or Kubernetes environment, it can continuously test whether a web application endpoint returns a successful HTTP response, whether a database port is reachable, or whether an ingress URL is accessible after deployment. When combined with Prometheus alerts and Grafana dashboards, it helps teams detect failed deployments, broken routing, unavailable containers, network issues, slow responses, and certificate problems before they impact users.

To run the stack follow the instructions bellow:
```bash
# Check the docker-compose file
cat docker-compose.blackbox-exporter.yaml
# Start Blackbox Exporter
sudo docker compose -f docker-compose.blackbox-exporter.yaml up -d
# Check the logs
sudo docker compose -f docker-compose.blackbox-exporter.yaml logs -f
```

After starting the stack wait a few moments for the services to initialize, then open Grafana at `http://{PUBLIC_BIND_IP}:3001/` and check the `Blackbox Exporter: Services availability` dashboard.

## Set up telemetry collector with Grafana Alloy

Grafana Alloy is an open-source telemetry collector used to collect, process, and forward observability data from applications and infrastructure. It is based on the OpenTelemetry Collector and includes built-in support for Prometheus-style pipelines, making it useful for collecting metrics, logs, traces, and profiles in one unified agent. Instead of running many separate collectors or agents for different telemetry signals, Alloy provides a single configurable component that can receive data from applications, scrape metrics, transform telemetry, and send it to observability backends such as Grafana, Prometheus-compatible systems, Loki, Tempo, or Pyroscope.

In a containerized application deployment, Grafana Alloy can be used as a central observability layer for Docker or Kubernetes workloads. It can collect container and application metrics, receive OpenTelemetry data from instrumented services, process logs, and forward traces to the appropriate backend for visualization and alerting. This helps teams understand how containers, services, and infrastructure behave during deployments and production operation. By using Alloy, organizations can simplify telemetry collection, reduce the number of separate monitoring agents, standardize observability pipelines, and gain a clearer view of application performance, reliability, and resource usage across their containerized environment.

> Grafana Alloy can reduce the number of separate observability agents in a containerized deployment by combining multiple telemetry collection functions into a single component. It can replace or embed functionality similar to Node Exporter for host metrics and Blackbox Exporter for endpoint probing, while also collecting logs, traces, and other telemetry signals.

To run the stack follow the instructions bellow:
```bash
# Check the docker-compose file
cat docker-compose.alloy.yaml
# Start Grafana Alloy
sudo docker compose -f docker-compose.alloy.yaml up -d
# Check the logs
sudo docker compose -f docker-compose.alloy.yaml logs -f
```

After starting the stack wait a few moments for the services to initialize, then open Grafana at `http://{PUBLIC_BIND_IP}:3001/` and check the `Alloy: Application Logs` dashboard.


## Runtime security with Falco

Runtime security is an important part of protecting containerized applications after they have already been deployed and started running. While image scanning and configuration checks help find problems before deployment, runtime security focuses on detecting suspicious behavior while containers, hosts, and Kubernetes workloads are active. This includes events such as unexpected shell access inside a container, sensitive file reads, privilege escalation attempts, unusual network activity, or processes behaving differently from what is expected. Runtime monitoring helps teams identify threats that only appear during execution, including compromised containers, misconfigured workloads, and attacks that bypass earlier security controls.

[Falco is an open-source](https://github.com/falcosecurity/falco) cloud-native runtime security tool used to detect abnormal behavior and potential security threats in real time. It monitors Linux kernel events and system calls, evaluates them against security rules, and generates alerts when suspicious activity is detected. In a containerized application deployment, Falco can be used to watch Docker or Kubernetes workloads for risky actions such as spawning a shell in a container, accessing host files, writing to sensitive directories, opening unexpected network connections, or running unauthorized binaries. By combining system-level visibility with container and Kubernetes metadata, Falco helps teams understand which pod, container, namespace, or workload triggered an alert, making it useful for incident detection, auditing, and improving the overall security posture of cloud-native environments.

To run the stack follow the instructions bellow:
```bash
# Check the docker-compose file
cat docker-compose.falco.yaml
# Start Falco
sudo docker compose -f docker-compose.falco.yaml up -d
# Check the logs
sudo docker compose -f docker-compose.falco.yaml logs -f
```

After starting the stack wait a few moments for the services to initialize, then open Grafana at `http://{PUBLIC_BIND_IP}:3001/` and check the `Falco: Runtime Security Events` dashboard.


## Cleaning
```bash
# Stop and remove the Dockhand container
sudo docker compose -f docker-compose.dockhand.yaml down -v
# Remove the observability network
sudo docker network rm observability_net
# Stop and remove the node exporter container
sudo docker compose -f docker-compose.node-exporter.yaml down -v
# Stop and remove the cAdvisor container
sudo docker compose -f docker-compose.cadvisor.yaml down -v
# Stop and remove the blackbox exporter container
sudo docker compose -f docker-compose.blackbox-exporter.yaml down -v
# Stop and remove the Grafana Alloy container
sudo docker compose -f docker-compose.alloy.yaml down -v
# Stop and remove the Falco container
sudo docker compose -f docker-compose.falco.yaml down -v
# Stop and remove the observability stack
sudo docker compose -f docker-compose.observability-stack.yaml down -v
```





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
