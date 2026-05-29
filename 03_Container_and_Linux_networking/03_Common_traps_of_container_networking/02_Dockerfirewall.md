# Chapter 2: Docker Firewall Reality, NAT, iptables, nftables, and DOCKER-USER

## Theory

This chapter comes early because it challenges one of the most common defender assumptions: that host firewall rules automatically protect Docker-published services in the same way they protect ordinary host services. A normal service listening directly on the host is usually reached through the host input path. A client connects to a host interface, packets are evaluated by the host firewall's input logic, and the packet is delivered to a local process.

A Docker-published service is different. When Docker publishes a container port, Docker creates firewall and NAT rules so traffic arriving on the host can be translated and forwarded to the container. The packet may be DNATed before it reaches the host input path that administrators are used to thinking about. In many Linux Docker deployments, published container traffic is better understood as NAT and forwarding traffic, not simply as traffic to a host-local process.

**Mechanism:** Docker uses Linux packet filtering and NAT to make private container addresses usable. For outbound traffic, Docker usually masquerades container source addresses behind the host. For inbound published ports, Docker creates destination NAT rules that translate traffic from a host-facing address and port to a container IP and port. That translation changes the packet path and the fields that later firewall rules may see.

**Security consequence:** a published port is not only an application setting; it is a host exposure and packet-forwarding decision. Controls written for ordinary host listeners may miss Docker-published traffic because the packet may be handled through NAT and `FORWARD`, not simply through `INPUT`.

This is why defenders need to understand `PREROUTING`, `OUTPUT`, `POSTROUTING`, `FORWARD`, Docker-created chains, and the `DOCKER-USER` chain. Docker creates firewall rules for bridge networking, port publishing, masquerading, and isolation. The `DOCKER-USER` chain exists so administrators can place user-defined filtering rules before Docker's own forwarding rules when Docker is using the iptables firewall backend. This does not make `DOCKER-USER` a complete security platform, but it is an important control point for Docker traffic on native Linux Docker hosts using the iptables backend.

A simplified packet path for a normal host service looks like this.

```text
remote client → host interface → filter/INPUT → local host process
```

A simplified packet path for a Docker-published service from another machine looks like this.

```text
remote client → host interface → nat/PREROUTING → DNAT to container IP:port
              → filter/FORWARD → DOCKER-USER → Docker chains → container
```

A simplified packet path for a host-local test is different and may vary by platform.

```text
host process → localhost or host IP → local routing, nat/OUTPUT, loopback behavior,
               docker-proxy behavior, or Docker Desktop forwarding behavior
```

The important operational point is that localhost testing is not a reliable proof of how externally arriving traffic is filtered. A host-local `curl http://127.0.0.1:8080` may not exercise the same path as traffic arriving on another interface. For this reason, the practical below creates a separate Linux network namespace that behaves like an external client. This makes the lab deterministic without requiring a second physical machine.

There is another expert-level detail: Docker's DNAT may already have happened by the time packets reach `DOCKER-USER`. If a service is published as `-p 8080:80`, a rule in `DOCKER-USER` that matches `--dport 80` may work while a rule matching `--dport 8080` may not. To match the original host-facing destination, defenders can use conntrack original-destination matching, but that should be used deliberately because it can have performance impact.

Docker's nftables backend changes the implementation. In Docker's nftables mode, there is no iptables `DOCKER-USER` chain. The equivalent idea is to add policy in separate nftables tables with base chains at the appropriate hook and priority. The security model is the same, but the mechanics are different. This hands-on firewall lab assumes the iptables backend.

Docker Desktop is also different. Docker Desktop runs Docker Engine inside a Linux VM and exposes ports through Docker Desktop backend processes. Compose, service discovery, and application segmentation labs work well on Docker Desktop, but host iptables packet-path labs are best run on a native Linux VM.

## Chapter 2 Verification Focus

This lab proves four things.

1. `-p 8080:80` is a host exposure decision.
2. Published Docker ports are not equivalent to ordinary host-local listeners.
3. `INPUT` is not the right enforcement point for forwarded Docker-published traffic.
4. `DOCKER-USER` can filter forwarded Docker traffic, but it normally sees the post-DNAT container destination unless conntrack original-destination matching is used.

## Pre-Flight Practical: Identify the Firewall Environment

Run these checks before changing firewall rules.

```bash
echo "[*] Docker version"
docker version

echo "[*] Docker info: rootless/firewall-related fields if present"
docker info | egrep -i 'rootless|firewall|iptables|nftables|userland|security' || true

echo "[*] iptables frontend"
sudo iptables -V

echo "[*] Is DOCKER-USER present?"
sudo iptables -S DOCKER-USER 2>/dev/null || true

echo "[*] Is nftables also present?"
sudo nft list ruleset 2>/dev/null | grep -i docker | head -n 20 || true
```

Observation: on the preferred lab host, `DOCKER-USER` exists and `iptables -V` returns an iptables frontend such as `iptables-nft` or `iptables-legacy`. If `DOCKER-USER` does not exist, do not force the rest of this chapter. Treat the host as a useful discussion case for nftables, rootless Docker, Docker Desktop, or a platform-managed environment.

## Red-Team Practical: Create a Deterministic External Client

Create a separate Linux network namespace to simulate a client arriving from another interface.

```bash
sudo ip netns del docker-ext 2>/dev/null || true
sudo ip link del veth-dhost 2>/dev/null || true

sudo ip netns add docker-ext

sudo ip link add veth-dhost type veth peer name veth-dclient
sudo ip link set veth-dclient netns docker-ext

sudo ip addr add 10.200.0.1/24 dev veth-dhost
sudo ip link set veth-dhost up

sudo ip netns exec docker-ext ip addr add 10.200.0.2/24 dev veth-dclient
sudo ip netns exec docker-ext ip link set lo up
sudo ip netns exec docker-ext ip link set veth-dclient up
sudo ip netns exec docker-ext ip route add default via 10.200.0.1

sudo ip netns exec docker-ext ip addr
sudo ip netns exec docker-ext ip route
```

Observation: the namespace has an interface with `10.200.0.2/24`, the host side has `10.200.0.1/24`, and the namespace default route points to `10.200.0.1`. This namespace is the lab's external client.

## Red-Team Practical: Prove a Published Port Is a Host Exposure Decision

Start a container with a published port.

```bash
docker rm -f fw-web 2>/dev/null || true

docker run -d \
  --name fw-web \
  -p 8080:80 \
  nginx:alpine
```

Inspect the exposure.

```bash
docker ps --filter name=fw-web
docker port fw-web
docker inspect fw-web | jq '.[0].NetworkSettings.Ports'
ss -tulpen | grep 8080 || true
```

Test from the simulated external client.

```bash
sudo ip netns exec docker-ext curl -I --max-time 3 http://10.200.0.1:8080
```

Observation: the request receives an HTTP response from nginx. Attacker perspective: `-p 8080:80` should be treated as an exposure decision. In many environments it binds broadly unless the publisher explicitly restricts the host IP.

## Blue-Team Practical: Observe NAT and Forwarding Counters

Zero relevant counters, generate traffic, and inspect the packet path.

```bash
sudo iptables -Z INPUT 2>/dev/null || true
sudo iptables -Z FORWARD 2>/dev/null || true
sudo iptables -Z DOCKER-USER 2>/dev/null || true
sudo iptables -t nat -Z PREROUTING 2>/dev/null || true
sudo iptables -t nat -Z DOCKER 2>/dev/null || true

sudo ip netns exec docker-ext curl -I --max-time 3 http://10.200.0.1:8080

echo "[*] INPUT"
sudo iptables -L INPUT -n -v --line-numbers

echo "[*] FORWARD"
sudo iptables -L FORWARD -n -v --line-numbers

echo "[*] DOCKER-USER"
sudo iptables -L DOCKER-USER -n -v --line-numbers

echo "[*] NAT PREROUTING"
sudo iptables -t nat -L PREROUTING -n -v --line-numbers

echo "[*] NAT DOCKER"
sudo iptables -t nat -L DOCKER -n -v --line-numbers
```

Observation: NAT and forwarding counters move. The exact chain names and counts vary, but the important result is that Docker-published traffic is not behaving like a simple local process behind `INPUT`.

## Red-Team Practical: Test the INPUT-Chain Misconception

Add an `INPUT` rule that appears to block the published host port from the simulated external interface.

```bash
sudo iptables -I INPUT 1 \
  -i veth-dhost \
  -p tcp \
  --dport 8080 \
  -j DROP
```

Test again.

```bash
sudo ip netns exec docker-ext curl -I --max-time 3 http://10.200.0.1:8080 || true
sudo iptables -L INPUT -n -v --line-numbers
```

Observation on the preferred native Linux iptables lab: the request still succeeds. The packet has been DNATed and forwarded to the container instead of being delivered to a local host process through `INPUT`. If the request fails, inspect the platform. You may be on Docker Desktop, a different firewall backend, a host with additional firewall policy, or a configuration using a different publishing path.

Remove the rule.

```bash
sudo iptables -D INPUT 1
```

## Blue-Team Practical: Enforce with DOCKER-USER Using the Container Port

Block traffic to the container destination port in `DOCKER-USER`.

```bash
sudo iptables -I DOCKER-USER 1 \
  -i veth-dhost \
  -p tcp \
  --dport 80 \
  -j DROP
```

Test again.

```bash
sudo ip netns exec docker-ext curl -I --max-time 3 http://10.200.0.1:8080 || true
sudo iptables -L DOCKER-USER -n -v --line-numbers
```

Observation: the request fails and the `DOCKER-USER` counter increments. Defensive interpretation: the rule matches destination port `80`, not `8080`, because Docker DNAT has already translated the original host-facing port to the container port.

Remove the rule.

```bash
sudo iptables -D DOCKER-USER 1
```

## Blue-Team Practical: Match the Original Published Host Port with Conntrack

Use conntrack original-destination matching when policy must be expressed in terms of the host-facing address and port.

```bash
sudo iptables -I DOCKER-USER 1 \
  -m conntrack \
  --ctstate ESTABLISHED,RELATED \
  -j ACCEPT

sudo iptables -I DOCKER-USER 2 \
  -i veth-dhost \
  -p tcp \
  -m conntrack \
  --ctorigdst 10.200.0.1 \
  --ctorigdstport 8080 \
  -j DROP
```

Test again.

```bash
sudo ip netns exec docker-ext curl -I --max-time 3 http://10.200.0.1:8080 || true
sudo iptables -L DOCKER-USER -n -v --line-numbers
```

Observation: the request fails, and the policy is now expressed in terms of the original host-facing destination `10.200.0.1:8080`. This is useful when a security policy must refer to the published port instead of the container port. Use this deliberately because conntrack matching can add overhead.

Remove the rules.

```bash
sudo iptables -D DOCKER-USER 2
sudo iptables -D DOCKER-USER 1
```

## Blue-Team Practical: Prefer Localhost Binds for Local-Only Services

Run a safer local-only bind.

```bash
docker rm -f fw-web-local 2>/dev/null || true

docker run -d \
  --name fw-web-local \
  -p 127.0.0.1:8081:80 \
  nginx:alpine
```

Test from the host and from the simulated external client.

```bash
curl -I --max-time 3 http://127.0.0.1:8081
sudo ip netns exec docker-ext curl -I --max-time 3 http://10.200.0.1:8081 || true
```

Observation: localhost succeeds and the simulated external client fails. Defensive interpretation: local-only administrative surfaces, reverse-proxy backends, and developer-only tools should bind explicitly to loopback when they do not need network exposure.

## Blue-Team Practical: Block Cloud Metadata from Containers

On cloud VMs, metadata access is a high-risk egress path. In a lab, demonstrate the policy without relying on a real cloud metadata service.

```bash
sudo iptables -I DOCKER-USER 1 -d 169.254.169.254/32 -j DROP
```

Test from a container.

```bash
docker run --rm curlimages/curl \
  -m 3 http://169.254.169.254/ || true
```

Inspect counters and remove the rule.

```bash
sudo iptables -L DOCKER-USER -n -v --line-numbers
sudo iptables -D DOCKER-USER -d 169.254.169.254/32 -j DROP
```

Observation: the request fails or times out, and the `DOCKER-USER` counter increments if the packet hit the chain. Defensive interpretation: egress control matters. Blocking inbound ports is not enough if a compromised container can reach metadata services, internal networks, or external attacker infrastructure.

## Blue-Team Practical: Allowlist Published Container Access

Replace `<trusted-ip>` with the source that should be allowed. In this lab, use `10.200.0.2` as the trusted source if you want the simulated external namespace to be allowed.

```bash
sudo iptables -I DOCKER-USER 1 \
  -m conntrack \
  --ctstate ESTABLISHED,RELATED \
  -j RETURN

sudo iptables -I DOCKER-USER 2 \
  -i veth-dhost \
  -p tcp \
  -s <trusted-ip> \
  --dport 80 \
  -j RETURN

sudo iptables -I DOCKER-USER 3 \
  -i veth-dhost \
  -p tcp \
  --dport 80 \
  -j DROP
```

Inspect counters.

```bash
sudo iptables -L DOCKER-USER -n -v --line-numbers
```

Remove the rules by line number in reverse order.

```bash
sudo iptables -D DOCKER-USER 3
sudo iptables -D DOCKER-USER 2
sudo iptables -D DOCKER-USER 1
```

Observation: the trusted source can reach the service and other sources cannot. Operational interpretation: an allowlist should be written in terms of the actual packet path and should include a clear owner, persistence mechanism, rollback path, and monitoring signal.

## Cleanup

```bash
docker rm -f fw-web fw-web-local 2>/dev/null || true

sudo ip netns del docker-ext 2>/dev/null || true
sudo ip link del veth-dhost 2>/dev/null || true
```

## Chapter 2 Review Commands

```bash
sudo iptables -S DOCKER-USER 2>/dev/null || true
sudo iptables -S DOCKER 2>/dev/null || true
sudo iptables -S FORWARD 2>/dev/null || true
sudo iptables -t nat -S | grep DOCKER || true
sudo conntrack -L 2>/dev/null | head || true
```

## Chapter 2 Core Points

Docker-published ports are exposure decisions.

Localhost tests are not sufficient proof of external packet-path behavior.

`INPUT` protects host-local delivery paths, not every path that uses a host IP and port.

`DOCKER-USER` is the right iptables-era control point for many forwarded Docker packets, but it usually sees post-DNAT container addresses and ports.

Conntrack original-destination matching can express policy in terms of the original host-facing address and port, but it should be used deliberately.

In nftables mode, Docker's implementation is different. The security model remains packet-path verification, but the control point is not the iptables `DOCKER-USER` chain.

---
