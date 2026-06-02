# Chapter 8: VPN Containers, Tailscale Sidecars, and Shared Network Namespaces

## Theory

VPN sidecars are a common pattern for routing container traffic through a secure tunnel. Instead of giving every application container its own VPN client, one container runs the VPN software and owns the network namespace. Other containers share that namespace.

Docker CLI uses:

```bash
--network container:<vpn-container>
```

Docker Compose uses:

```yaml
network_mode: "service:tailscale"
```

In this model, the application container does not receive its own interfaces, routes, DNS configuration, or localhost. It inherits all networking from the VPN container.

**Mechanism:** namespace-sharing containers use the same Linux network namespace. Interfaces, routing tables, DNS settings, listening sockets, localhost, firewall rules, and VPN tunnel interfaces are shared.

**Security consequence:** the VPN container becomes an egress gateway, routing policy, DNS policy, firewall boundary, and observability boundary. A compromised application container can interact with localhost services and network paths that exist inside the shared namespace.

Common risks include:

* shared localhost access
* unintended DNS leakage
* incorrect port publishing assumptions
* tunnel bypass during VPN failures
* reduced visibility when ownership is unclear

This chapter uses Tailscale as the VPN sidecar because it is widely deployed and demonstrates the pattern clearly.

---

## Environment Preparation

Create a dedicated lab directory.

```bash
mkdir -p ~/docker-network-security-lab/ch08-vpn
cd ~/docker-network-security-lab/ch08-vpn
```

Create a state directory for Tailscale.

```bash
mkdir -p tailscale-state
```

---

## Blue-Team Practical: Build a VPN Sidecar Environment

Create `compose-vpn.yml`.

```bash
cat > compose-vpn.yml <<'YAML'
services:
  tailscale:
    image: tailscale/tailscale:latest
    container_name: tailscale
    hostname: ts-demo

    cap_add:
      - NET_ADMIN
      - NET_RAW

    devices:
      - /dev/net/tun:/dev/net/tun

    environment:
      TS_STATE_DIR: /var/lib/tailscale

    volumes:
      - ./tailscale-state:/var/lib/tailscale

    command: tailscaled

    restart: unless-stopped

  app:
    image: ubuntu:24.04
    container_name: vpn-app

    network_mode: "service:tailscale"

    depends_on:
      - tailscale

    command:
      - bash
      - -c
      - |
        apt update &&
        apt install -y \
          curl \
          iproute2 \
          iputils-ping \
          dnsutils \
          netcat-openbsd \
          tcpdump &&
        tail -f /dev/null
YAML
```

Start the environment.

```bash
docker compose -f compose-vpn.yml up -d
```

Verify containers.

```bash
docker ps --filter name=tailscale
docker ps --filter name=vpn-app
```

Observation: the application container starts without its own Docker network attachment and instead shares the Tailscale namespace.

---

## Blue-Team Practical: Authenticate the VPN

Interactive authentication.

```bash
docker exec tailscale tailscale up
```

Or use an auth key.

```bash
docker exec tailscale \
  tailscale up \
  --authkey=tskey-auth-xxxxxxxx
```

Verify status.

```bash
docker exec tailscale tailscale status
```

Observation: Tailscale reports an assigned address and visible peers.

Defensive interpretation: the VPN container now owns the network namespace used by both containers.

---

## Red-Team Practical: Verify Shared Interfaces and Routes

Inspect networking from the application container.

```bash
docker exec -it vpn-app bash
```

Inside the container:

```bash
ip addr
ip route
cat /etc/resolv.conf
exit
```

Inspect the VPN container.

```bash
docker exec tailscale ip addr
docker exec tailscale ip route
docker exec tailscale cat /etc/resolv.conf
```

Observation: interfaces, routes, and DNS configuration are identical.

Attacker perspective: the application container does not have an independent network stack.

---

## Red-Team Practical: Demonstrate Shared Localhost

Start a listener inside the VPN container.

```bash
docker exec tailscale sh -c '
apk update &&
apk add netcat-openbsd &&
nc -l -p 9090
'
```

In another terminal, send traffic from the application container.

```bash
docker exec vpn-app bash -c \
'echo "shared localhost test" | nc 127.0.0.1 9090'
```

Observation: the VPN container receives the message.

Attacker perspective: localhost is shared across containers that share a network namespace.

---

## Blue-Team Practical: Demonstrate Namespace-Owned Port Publishing

Stop the environment.

```bash
docker compose -f compose-vpn.yml down
```

Replace the entire `compose-vpn.yml` with the following configuration (no manual editing required).

```bash
cat > compose-vpn.yml <<'YAML'
services:
  tailscale:
    image: tailscale/tailscale:latest
    container_name: tailscale
    hostname: ts-demo

    cap_add:
      - NET_ADMIN
      - NET_RAW

    devices:
      - /dev/net/tun:/dev/net/tun

    environment:
      TS_STATE_DIR: /var/lib/tailscale

    volumes:
      - ./tailscale-state:/var/lib/tailscale

    ports:
      - "127.0.0.1:9090:9090"

    command: tailscaled

    restart: unless-stopped

  app:
    image: ubuntu:24.04
    container_name: vpn-app

    network_mode: "service:tailscale"

    depends_on:
      - tailscale

    command:
      - bash
      - -c
      - |
        apt update &&
        apt install -y           curl           iproute2           iputils-ping           dnsutils           netcat-openbsd           tcpdump &&
        tail -f /dev/null
YAML
```

Restart the environment.

```bash
docker compose -f compose-vpn.yml up -d
```

Start a listener inside the application container.

```bash
docker exec vpn-app bash -c \
'nc -l -p 9090'
```

From the Docker host:

```bash
nc -vz 127.0.0.1 9090
```

Observation: the connection succeeds even though the listening process runs in the application container.

Defensive interpretation: published ports belong to the namespace-owning VPN container, not to the namespace-sharing application container.

---

## Red-Team Practical: Observe Traffic Through the VPN Namespace

Start packet capture inside the VPN container.

```bash
docker exec tailscale sh -c '
apk update &&
apk add tcpdump &&
tcpdump -i any
'
```

In another terminal, generate traffic from the application container.

```bash
docker exec vpn-app bash -c '
curl -I http://example.com
ping -c 2 1.1.1.1
'
```

Observation: traffic generated by the application container appears in captures taken inside the VPN container.

Attacker perspective: all application traffic traverses the VPN namespace.

---

## Blue-Team Practical: Verify Tunnel Dependency

Stop the VPN container.

```bash
docker stop tailscale
```

Attempt outbound access.

```bash
docker exec vpn-app bash -c \
'curl -I http://example.com'
```

Observation: connectivity fails because the application does not possess an independent network namespace.

Defensive interpretation: namespace sharing can act as a strong containment mechanism because the application cannot simply route around the VPN.

Restart the VPN container.

```bash
docker start tailscale
```

---

## Blue-Team Practical: Configure an Exit Node

On another Tailscale-connected system:

```bash
sudo tailscale up --advertise-exit-node
```

Configure the VPN container to use that exit node.

```bash
docker exec tailscale \
  tailscale up \
  --exit-node=<TAILSCALE-IP>
```

Verify routing from the application container.

```bash
docker exec vpn-app bash -c \
'curl ifconfig.me'
```

Observation: the public IP matches the exit node rather than the local Docker host.

Defensive interpretation: exit nodes convert the deployment from mesh connectivity into full-tunnel VPN egress.

---

## Blue-Team Practical: Verify DNS Handling

Inspect resolver configuration.

```bash
docker exec tailscale cat /etc/resolv.conf
docker exec vpn-app cat /etc/resolv.conf
```

Generate DNS traffic.

```bash
docker exec vpn-app bash -c '
dig example.com
dig openai.com
'
```

Observation: both containers use the same resolver configuration.

Defensive interpretation: DNS policy is inherited from the VPN namespace. DNS-leak testing should be part of VPN validation.

---

## Chapter 8 Verification Commands

```bash
docker inspect tailscale

docker inspect vpn-app

docker exec tailscale ip addr
docker exec tailscale ip route

docker exec vpn-app ip addr
docker exec vpn-app ip route

docker exec tailscale tailscale status

docker exec tailscale cat /etc/resolv.conf
docker exec vpn-app cat /etc/resolv.conf
```

---

## Chapter 8 Core Points

VPN sidecars work by sharing a network namespace.

`network_mode: "service:tailscale"` gives the application container the VPN container's interfaces, routes, DNS configuration, and localhost.

Localhost is shared across namespace-sharing containers.

Published ports belong to the namespace owner.

All application traffic traverses the VPN namespace.

DNS behavior, firewall policy, and routing policy are inherited from the VPN container.

VPN sidecars should be treated as egress gateways and security boundaries, not merely privacy tools.

---

## Cleanup

```bash
docker compose -f compose-vpn.yml down

rm -rf tailscale-state
```
