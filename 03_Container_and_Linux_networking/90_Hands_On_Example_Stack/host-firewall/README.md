# Host Firewall Notes

Use this folder only on a Linux lab VM where you have console access.

The key lesson is not the exact script. The key lesson is where Docker-aware filtering belongs:

- use the `DOCKER-USER` chain
- do not edit Docker-managed chains directly

Why:

- Docker inserts its own forwarding rules when ports are published
- generic host firewall guides often miss that behavior
- rules in `DOCKER-USER` run before Docker's own forwarding rules

Typical policy for this lab:

- allow the published edge web port
- allow management-only ports from a trusted admin subnet
- drop direct access to backend, PostgreSQL, and Redis if they ever become published by mistake

Example:

```bash
sudo ./host-firewall/apply-docker-user-rules.sh eth0 8080 192.0.2.0/24
```

Arguments:

1. host interface
2. published web port
3. trusted management subnet

If you use UFW on Linux, validate carefully. Docker's own packet handling can bypass assumptions people make about front-end firewall tools if they are not Docker-aware.
