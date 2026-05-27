# Hands On: Container Monitoring And Observability

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
