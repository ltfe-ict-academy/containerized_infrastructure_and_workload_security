# Chapter 9: Operational Ownership, Policy Persistence, and Incident Response Mapping

## Theory

Docker network security fails in real organizations when the controls are technically correct but operationally orphaned. A rule inserted by hand during an incident may prove the packet path, but it is not a mature control until it has an owner, a persistence mechanism, a review process, a test, and monitoring. Mature review asks not only whether a packet is allowed, but also who decided that it should be allowed and where that decision is recorded.

A mature Docker network control usually exists at multiple layers. Cloud security groups or network ACLs may restrict which sources can reach a host. Host firewall policy may restrict forwarding, metadata access, and sensitive destinations. Docker network design controls which containers can discover and reach each other. Compose files document intended service relationships. Application authentication controls whether a reachable service is usable. Runtime visibility maps suspicious behavior to a container, image, process, command line, and user.

No single layer should be treated as complete. Cloud firewalls may not see container-to-container traffic on the same host. Host firewalls may not understand application identity. Compose networks may not prevent a compromised multi-network service from pivoting. Application authentication may not stop metadata probing or DNS exfiltration. Runtime visibility may detect a problem after the path has already been used. Defense comes from explicit design and overlapping controls.

**Mechanism:** Docker network policy often exists across several systems at once: Compose defines network membership and published ports, Docker creates packet-filtering and NAT state, the host firewall applies local policy, cloud networking controls external access, and runtime telemetry provides workload context. None of these layers owns the whole truth by itself.

**Security consequence:** a command typed during a lab is not a durable control. A durable control has an owner, a definition in the correct system of record, persistence across daemon restarts and redeployments, a verification method, monitoring, and a rollback path.

## Policy Ownership Checklist

For each published port, network, firewall rule, or exception, answer these questions.

| Question | Example answer |
|---|---|
| What business function requires this path? | Public HTTPS to reverse proxy, API to database, backup job to object storage |
| Who owns the path? | Platform team, application team, security team, SRE team |
| Where is it defined? | Compose file, Terraform, Ansible, systemd unit, daemon configuration, firewall manager |
| How is it persisted? | Version-controlled infrastructure-as-code, documented host baseline, managed firewall policy |
| How is it tested? | CI linting, deployment tests, port scans from a lab network, container reachability tests |
| How is it monitored? | Flow logs, DNS logs, eBPF events, firewall counters, SIEM alerts |
| How is it removed? | Change request, pull request, rule expiration, cleanup command, rollback plan |

## Practical: Convert a Temporary Rule into an Operational Control

Start with a temporary rule from earlier chapters.

```bash
sudo iptables -I DOCKER-USER 1 -d 169.254.169.254/32 -j DROP
sudo iptables -L DOCKER-USER -n -v --line-numbers
```

Document it as a control.

```text
Control: Block container access to cloud metadata endpoint
Owner: Platform Security
Scope: Docker bridge traffic on Linux hosts using iptables backend
Reason: Prevent compromised containers from querying instance metadata credentials
Implementation: DOCKER-USER drop rule for 169.254.169.254/32
Persistence: managed host firewall role or equivalent host baseline
Verification: container curl to metadata endpoint times out; rule counter increments
Exceptions: none without security approval
Rollback: remove exact managed rule and redeploy host firewall baseline
Monitoring: alert on attempted metadata access if runtime or flow telemetry is available
```

Observation: the command proves enforcement. The control record makes the control maintainable.

Remove the temporary rule.

```bash
sudo iptables -D DOCKER-USER -d 169.254.169.254/32 -j DROP
```

## Incident Response Mapping Practical

Given a suspicious connection such as this:

```text
172.18.0.5 → 10.0.8.20:5432
```

Map it back to workload context.

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Networks}}\t{{.Ports}}'

docker inspect $(docker ps -q) \
  | jq -r '.[] | .Name as $name | .Config.Image as $image | .NetworkSettings.Networks | to_entries[] | "\($name) \($image) \(.key) \(.value.IPAddress)"'
```

If the container is still running, map it to a host PID and network namespace.

```bash
CONTAINER=<container-name>
PID=$(docker inspect -f '{{.State.Pid}}' "$CONTAINER")
echo "$CONTAINER pid=$PID"
sudo nsenter -t "$PID" -n ss -tupen || true
sudo nsenter -t "$PID" -n ip route
```

If eBPF telemetry is available, enrich the mapping with process context.

```text
container: api
image: registry.example.com/payments-api:2026.05.18
process: python
parent: gunicorn
command_line: python worker.py
uid: 10001
destination: 10.0.8.20:5432
meaning: application worker connected to database or an attacker reused application credentials/path
```

Observation: the responder can move from an IP address to a container, image, process, command line, and owner. Operational interpretation: attribution is not optional. Without attribution, network security becomes a pile of IP addresses and guesses.

## Configuration Review Themes

A Docker networking review should include these questions.

- Which services publish host ports, and are they bound to the correct host address?
- Which services use `network_mode: host`, `network_mode: none`, or `network_mode: service:<name>`?
- Which containers join more than one network and therefore become potential pivots?
- Which networks are marked `internal: true`, and what egress path remains available?
- Which services rely on predictable DNS names such as `db`, `redis`, `adminer`, or `grafana`?
- Which containers have `NET_ADMIN`, `NET_RAW`, privileged mode, or the Docker socket?
- Which paths are controlled by Compose design, which by host firewall, which by cloud firewall, and which by application authentication?
- Which controls cover IPv6 as well as IPv4?
- Which controls behave differently on Docker Desktop, rootless Docker, or nftables hosts?
- Which suspicious connections can be attributed to process and container context?

---
