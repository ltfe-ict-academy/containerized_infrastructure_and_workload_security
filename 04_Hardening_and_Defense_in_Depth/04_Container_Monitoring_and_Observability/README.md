# Container Monitoring And Observability

Hardening helps reduce impact.

Secrets management helps reduce what can be stolen.

But neither helps much if defenders cannot answer basic questions during an incident:

- what is happening right now?
- which service is failing or being abused?
- when did it start?
- what changed just before it happened?
- where did the request go next?

That is why monitoring and observability matter.

This module is about giving defenders enough telemetry to see both reliability problems and security problems in containerized environments.

## Where This Fits In Part 04

This is the closing lecture in the defense-in-depth section.

The red line across Part 04 is:

1. web apps are attacked first
2. hardening limits the blast radius
3. secret management limits the value of compromise
4. observability lets us detect, investigate, and respond

This module covers step 4.

## Learning Objectives

By the end of this lecture, participants should be able to:

- explain the difference between basic monitoring and true observability
- identify the most important telemetry signals for containerized workloads
- design a practical telemetry stack for a small production Docker environment
- explain how logs, metrics, traces, events, and runtime detections fit together
- avoid common observability mistakes such as secret leakage in logs, cardinality explosions, and missing deployment context

## Suggested Timing

This module works well as a 55-60 minute lecture:

| Time | Topic |
| --- | --- |
| 0-10 min | Monitoring versus observability |
| 10-22 min | The telemetry signals that matter |
| 22-38 min | Practical container observability architecture |
| 38-50 min | Security-relevant use cases and incident response |
| 50-60 min | Best practices and common mistakes |

## Monitoring Versus Observability

Participants often use these terms interchangeably.

They are related, but not identical.

Monitoring asks:

- is the service up?
- is CPU high?
- are error rates spiking?

Observability asks:

- why is the service failing?
- which request path is causing the issue?
- which deployment introduced the regression?
- which container, node, process, or user action explains what we are seeing?

Good monitoring is necessary.

Good observability is what makes a complex containerized environment explainable.

## The Telemetry Signals That Matter

For this course, teach five main signal types:

1. metrics
2. logs
3. traces
4. events
5. runtime security signals

Together, they let defenders move from symptoms to causes.

## 1. Metrics

Metrics are numeric measurements over time.

For containerized services, the most useful metrics usually include:

- request rate
- error rate
- latency
- saturation
- container CPU
- memory usage
- restart count
- network throughput
- queue depth
- DB or cache health metrics

These are what help you notice:

- a crash loop
- a resource exhaustion attack
- a slow downstream dependency
- an abuse spike

## 2. Logs

Logs give detail and context.

For production containers, logs should normally go to `stdout` and `stderr` so the platform can collect them cleanly.

Useful log sources:

- application logs
- reverse proxy logs
- authentication logs
- database logs where appropriate
- container runtime logs
- security-tool alerts

Structured logs are much easier to search, correlate, and alert on than ad hoc text strings.

## 3. Traces

Traces show how a single request moves through the system.

This is extremely valuable in modern stacks because a user request often touches:

- reverse proxy
- frontend
- backend API
- database
- cache
- external API

Without tracing, teams often argue about where the problem is.

With tracing, they can follow the request path directly.

Security value:

- traces help show suspicious request patterns
- they make lateral effects of one request easier to follow
- they expose where a malicious request triggered expensive or unusual downstream behavior

## 4. Events

Events are state changes.

Examples:

- container started
- container exited
- healthcheck failed
- image changed
- deployment restarted
- secret rotated
- daemon event triggered

Events matter because many incidents are really "bad change plus bad traffic."

If you cannot correlate the traffic spike with the deployment or restart that preceded it, investigations get slower and noisier.

## 5. Runtime Security Signals

Traditional observability focuses on performance and correctness.

Security-focused observability adds:

- suspicious process execution
- unexpected file access
- privilege escalation attempts
- unusual outbound connections
- shell spawned in web container
- read access to sensitive files

This is where tools like Falco become relevant.

Falco is not your whole observability stack.

But it is a valuable runtime signal source for defenders.

## What To Observe In A Containerized Application Stack

For a typical single-node stack, a good baseline includes:

## Application Layer

- request latency
- request rate
- 4xx and 5xx rates
- authentication failures
- slow queries
- business-critical failures

## Container Layer

- CPU
- memory
- disk usage where relevant
- restart count
- health status
- exit reasons

## Host Layer

- CPU pressure
- memory pressure
- filesystem capacity
- network errors
- packet drops
- daemon health

## Change Layer

- new image deployed
- config changed
- secret rotated
- compose or stack restart

## Security Layer

- suspicious execs
- outbound connection anomalies
- access to `/run/secrets` or sensitive paths
- repeated authentication failures
- unusual admin API access

## A Practical Single-Node Observability Pattern

For the kind of Docker-based environment used in this course, a realistic pattern is:

```text
application instrumentation
-> OpenTelemetry SDK / auto-instrumentation
-> collector or agent
-> metrics backend + logs backend + traces backend
-> dashboards + alerting
```

A very teachable open stack is:

- Prometheus for metrics
- cAdvisor for container metrics
- node_exporter for host metrics
- Loki for logs
- Grafana for dashboards
- OpenTelemetry for instrumentation and trace/metric/log export pipelines
- Alertmanager for alerts
- Falco for runtime security detections

That is more than enough for a serious single-node teaching environment.

## Why OpenTelemetry Matters

OpenTelemetry is important because it gives a vendor-neutral way to generate, collect, and export telemetry.

That matters for teaching because participants should not leave thinking observability equals one vendor product.

What matters is the model:

- instrument the application
- collect the telemetry
- process it
- export it to the backend of choice

The OpenTelemetry Collector is especially useful as a control point because it can receive, process, and forward telemetry centrally.

## Why Prometheus Still Matters

Prometheus remains one of the most important metrics tools in cloud-native environments because it gives you:

- time-series storage
- scraping model
- labels for dimensional analysis
- alerting integration

It is a very practical choice for:

- container resource metrics
- application metrics
- host metrics
- availability checks

## Why Logs Still Need Design

Many teams think:

"we have logs, so observability is covered."

Usually what they really have is:

- unstructured text
- inconsistent timestamps
- too much noise
- too little context
- secrets accidentally printed in debug output

Log best practices for containers:

- write to `stdout` and `stderr`
- use structured logs where practical
- include request IDs or trace IDs
- avoid logging secrets, tokens, and full credentials
- define retention and rotation

Docker's logging docs also make an operational point worth teaching:

the `local` logging driver is optimized for performance and disk usage, and its defaults include rotation and compression behavior.

Log handling is both an observability concern and a disk-exhaustion concern.

## Why cAdvisor And Host Metrics Matter

If the app is slow, the root cause might be:

- application code
- the database
- the host under memory pressure
- another noisy container

cAdvisor helps with container-level resource visibility.

Host exporters help with node-level context.

Without both, teams often blame the wrong layer.

## Health Checks Matter Too

Health checks are not full observability.

But they are useful signals.

A healthcheck should help answer:

- is the container alive?
- is the service ready to serve traffic?

That matters for:

- orchestration decisions
- restart behavior
- alerting context

Do not confuse "the process is running" with "the service is healthy."

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
