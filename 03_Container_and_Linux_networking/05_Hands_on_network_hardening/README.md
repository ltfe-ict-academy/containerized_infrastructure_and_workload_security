# Hands-On: Network Hardening

## Setup
- Use host firewall rules carefully; Docker can add its own iptables / nftables rules.
- Use internal: true for networks that should not have external connectivity.
- Publish only required ports.
- Bind host ports to 127.0.0.1 when traffic should only be local or behind a reverse proxy.
- Segment networks: frontend, backend, database/admin networks as separate networks.
- Avoid network_mode: host unless absolutely necessary.
- segment services onto the minimum necessary networks
- keep data stores off edge-facing networks
- add a reverse proxy for the deployment (hardened nginx)

