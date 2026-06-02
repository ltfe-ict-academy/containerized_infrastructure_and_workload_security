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

Attacker perspective: all application traffic is generated inside the shared VPN-sidecar network namespace. This proves namespace sharing, but it does not by itself prove that the traffic is encrypted or routed through the VPN tunnel.

---

## Blue-Team Practical: Verify Tunnel Dependency Carefully

Do not assume that namespace sharing automatically creates a VPN kill switch.

The application container depends on the VPN container's network namespace, but that namespace may still contain Docker's normal `eth0` interface and default bridge route. If the VPN process is stopped, unauthenticated, or not enforcing full-tunnel routing, ordinary internet traffic may still leave through the Docker bridge.

Inspect the route selected for public internet traffic.

```bash
docker exec vpn-app bash -c \
'ip route get 1.1.1.1'
```

Generate a normal internet request.

```bash
docker exec vpn-app bash -c \
'curl -I --connect-timeout 5 https://example.com || true'
```

Observation: if the route points to `eth0` through a Docker bridge gateway, traffic is not being forced through a VPN tunnel.

Defensive interpretation: a VPN sidecar gives the application a shared network namespace. It does not automatically guarantee fail-closed egress. A kill switch or explicit firewall policy is required if bridge egress must be blocked when the VPN is inactive.

---

## Red-Team and Blue-Team Practical: Demonstrate Bridge Leakage and Fix It

This lab intentionally creates a fail-open sidecar. The application still shares the sidecar network namespace, but the Tailscale daemon is not started. The goal is to prove that traffic can still leave through Docker's normal bridge route when no kill switch is present.

Stop the previous environment.

```bash
docker compose -f compose-vpn.yml down
```

Create `compose-vpn-leak.yml`.

```bash
cat > compose-vpn-leak.yml <<'YAML'
services:
  tailscale:
    image: tailscale/tailscale:latest
    container_name: tailscale-leak
    hostname: ts-leak

    cap_add:
      - NET_ADMIN
      - NET_RAW

    devices:
      - /dev/net/tun:/dev/net/tun

    environment:
      TS_STATE_DIR: /var/lib/tailscale

    volumes:
      - ./tailscale-state:/var/lib/tailscale

    command:
      - sh
      - -c
      - |
        echo "tailscaled intentionally not started"
        sleep infinity

    restart: unless-stopped

  app:
    image: ubuntu:24.04
    container_name: vpn-app-leak

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
          ca-certificates \
          iproute2 \
          iputils-ping \
          dnsutils \
          netcat-openbsd \
          tcpdump &&
        tail -f /dev/null
YAML
```

Start the leakage environment.

```bash
docker compose -f compose-vpn-leak.yml up -d
```

Confirm that the sidecar container is alive but the VPN daemon is inactive.

```bash
docker exec tailscale-leak sh -c 'tailscale status || true'
```

Observation: the command fails or reports that it cannot connect to `tailscaled`.

Inspect the route used for public internet traffic from the application container.

```bash
docker exec vpn-app-leak ip route

docker exec vpn-app-leak ip route get 1.1.1.1
```

Observation: the default route points through `eth0` to the Docker bridge gateway.

Generate internet traffic from the application container.

```bash
docker exec vpn-app-leak curl -I --connect-timeout 5 https://example.com
```

Observation: the request succeeds even though Tailscale is not running.

Attacker perspective: the application is still using the sidecar namespace, but traffic is leaking through Docker bridge egress instead of being forced through a VPN tunnel.

### Observe the leak from the Docker host

Identify the Docker bridge, sidecar IP, and host uplink interface.

```bash
SIDE=tailscale-leak
APP=vpn-app-leak

NET=$(docker inspect "$SIDE" \
  -f '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' | head -n1)

BR=$(docker network inspect "$NET" \
  -f '{{ index .Options "com.docker.network.bridge.name" }}')

[ -z "$BR" ] && \
BR="br-$(docker network inspect "$NET" -f '{{.Id}}' | cut -c1-12)"

IP=$(docker inspect "$SIDE" \
  -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

UPLINK=$(ip route get 1.1.1.1 | awk '
  {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}
')

echo "Compose network: $NET"
echo "Docker bridge:   $BR"
echo "Sidecar IP:      $IP"
echo "Host uplink:     $UPLINK"
```

Capture the traffic before Docker NAT on the bridge interface.

```bash
sudo tcpdump -ni "$BR" "host $IP"
```

In another terminal, generate traffic.

```bash
docker exec "$APP" curl -I --connect-timeout 5 https://example.com
```

Observation: the capture on the Docker bridge shows traffic sourced from the sidecar namespace IP.

Capture the traffic after Docker NAT on the host uplink.

```bash
sudo tcpdump -ni "$UPLINK" "tcp and port 443"
```

In another terminal, generate traffic again.

```bash
docker exec "$APP" curl -I --connect-timeout 5 https://example.com
```

Observation: the capture on the uplink shows the same egress path after NAT. The original container IP is usually no longer visible because Docker has masqueraded the traffic behind the host IP.

### Fix the leak with a host-level kill switch

Add a host firewall rule in the `DOCKER-USER` chain. This chain is evaluated before Docker's own forwarding rules and is the correct place for host-admin container forwarding policy.

```bash
sudo iptables -I DOCKER-USER 1 \
  -i "$BR" \
  -s "$IP" \
  -o "$UPLINK" \
  -j REJECT
```

Retest outbound access from the application container.

```bash
docker exec "$APP" curl -I --connect-timeout 5 https://example.com || \
echo "blocked by DOCKER-USER kill switch"
```

Observation: the request fails after the rule is installed.

Confirm that the rule is being hit.

```bash
sudo iptables -L DOCKER-USER -v -n --line-numbers
```

Defensive interpretation: the kill switch blocks fail-open Docker bridge egress from the shared sidecar namespace. The application can no longer bypass the inactive VPN tunnel by using the ordinary Docker bridge route.

Remove the lab rule when finished.

```bash
sudo iptables -D DOCKER-USER 1
```

Production note: this lab rule blocks all forwarded bridge egress from the sidecar namespace IP. In a production design, allow rules may be required for the VPN daemon's own control-plane and peer traffic, while still blocking application bypass traffic. A sidecar pattern should therefore be combined with explicit egress policy rather than treated as a kill switch by itself.

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

All application traffic is generated inside the VPN sidecar namespace, but traffic is only tunneled when routing and firewall policy force it through the VPN path.

DNS behavior, firewall policy, and routing policy are inherited from the VPN container.

Without a kill switch, a sidecar namespace can fail open and leak traffic through Docker bridge egress.

VPN sidecars should be treated as egress gateways and security boundaries, not merely privacy tools.

---

## Cleanup

```bash
docker compose -f compose-vpn.yml down

docker compose -f compose-vpn-leak.yml down 2>/dev/null || true

rm -rf tailscale-state
```
