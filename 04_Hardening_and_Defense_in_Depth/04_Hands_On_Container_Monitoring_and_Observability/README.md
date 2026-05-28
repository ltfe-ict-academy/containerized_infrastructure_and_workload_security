# Hands On: Container Monitoring And Observability

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

## Presequisites

Before starting this lab, make sure you have:
```bash
# Move to the working directory
cd ~/containerized_infrastructure_and_workload_security/04_Hardening_and_Defense_in_Depth/04_Hands_On_Container_Monitoring_and_Observability/example_app_final

# Create the .env file for the practical setup
chmod +x ./scripts/create_env_file.sh
./scripts/create_env_file.sh
# Create local secret files
chmod +x ./scripts/create-local-secrets.sh
./scripts/create-local-secrets.sh
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


## Run the observability stack (Prometheus, Grafana, Loki, Tempo)

The observability stack consists of Prometheus, Grafana, Loki, and Tempo working together to provide full visibility into the health, performance, and behavior of applications and infrastructure. Each component is responsible for a different type of telemetry data. [Prometheus](https://github.com/prometheus/prometheus) collects and stores metrics such as CPU usage, memory consumption, request rates, and application performance indicators. [Loki](https://github.com/grafana/loki) aggregates and stores logs generated by containers and services, while [Tempo](https://github.com/grafana/tempo) collects distributed traces that show how requests move through different services in a microservice environment. [Grafana](https://github.com/grafana/grafana) acts as the central visualization platform that connects all of these data sources into a unified interface.

Running the observability stack in a containerized deployment allows teams to monitor applications, infrastructure, and Kubernetes workloads in real time. Prometheus continuously scrapes metrics from exporters and instrumented applications, Loki collects logs from containers and system services, and Tempo stores trace information that helps identify latency issues and service dependencies. Grafana dashboards combine metrics, logs, and traces into a single view, making it easier to troubleshoot incidents, correlate events, and perform root cause analysis. This integrated approach improves operational visibility, accelerates debugging, and helps maintain reliable and scalable cloud-native applications.

The observability stack is especially useful in distributed systems and microservice-based architectures, where issues may span multiple containers, nodes, or services. By combining metrics, logs, and traces, teams can move from detecting a problem to identifying its exact cause more efficiently. For example, an alert in Prometheus can be correlated with related logs in Loki and request traces in Tempo directly from Grafana. This enables faster incident response, proactive monitoring, and better understanding of application behavior under production workloads.

In the Prometheus config (`./observability/prometheus/prometheus.yml`) change the server IP under `job_name: app-http-probes` job to match your server IP address. This is necessary for Prometheus to scrape the health check metrics from the application.

To run the stack follow the instructions bellow:
```bash
# Check the docker-compose file
cat docker-compose.observability-stack.yaml

# Start the stack
sudo docker compose -f docker-compose.observability-stack.yaml up -d
# Check the logs
sudo docker compose -f docker-compose.observability-stack.yaml logs -f
```

Grafana will be available at `http://{PUBLIC_BIND_IP}:3001/` with the credentials from the `.env` file.

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


## Cleaning the environment
```bash
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
# Remove the app
sudo docker compose -f docker-compose.yaml down -v
# Stop and remove the Dockhand container
sudo docker compose -f docker-compose.dockhand.yaml down -v
# Remove the observability network
sudo docker network rm observability_net
```

## Operational And Security Best Practices
- Keep observability private. Grafana, Prometheus, Loki, Tempo, cAdvisor, Dockhand, and Portainer are powerful operational interfaces. In production, put them behind SSO, network policy, TLS, and role-based access.
- Treat the Docker socket as a high-risk control surface. Alloy, Dockhand, Portainer, Docker events, and Falco use the Docker socket or host visibility to inspect the environment. That visibility is useful, but it is also sensitive. Do not expose these services publicly, and do not run untrusted containers on the same host with access to observability credentials.
- Collect enough data, but not everything forever. Metrics retention, log retention, and trace sampling should match the investigation window you need.
- Do not log secrets. Centralized logging makes investigation easier, but it also concentrates risk. Avoid printing tokens, database passwords, private keys, authorization headers, or full session cookies. Add redaction at the application, proxy, and collector layers.
- Alert on behavior, not only availability. CPU and memory alerts are useful, but security teams also need alerts for shell execution, sensitive file access, image pulls from unexpected registries, Docker daemon reloads, repeated restarts, and unexpected `exec` sessions.
- Pin and verify observability images. In a production baseline, pin versions or digests. Falco official images are signed and can be verified with `cosign`.
- Monitor the monitoring stack. A stopped log collector, a down Prometheus target, or a broken Falco sensor is itself a security signal. The absence of telemetry should be visible. You can monitor all the services with Grafana at `http://{PUBLIC_BIND_IP}:3001/` and check the `Monitoring Stack: Component Health` dashboard.

