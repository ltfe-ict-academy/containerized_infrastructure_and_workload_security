# Chapter 8: VPN Containers, Tailscale Sidecars, and Shared Network Namespaces

## Theory

Modern containerized VPN deployments commonly use a sidecar networking model. One container runs the VPN client and owns the network namespace, while one or more application containers share that namespace. In Docker CLI, this is done with:

```bash
--network container:<vpn-container>
```

In Docker Compose, this is commonly implemented as:

```yaml
network_mode: "service:vpn"
```

In this chapter, the VPN sidecar is implemented using Tailscale, a WireGuard-based mesh VPN platform. The application container does not have its own network stack. Instead, it inherits the VPN container’s interfaces, routes, DNS behavior, localhost, firewall rules, and VPN tunnel interfaces.

This architecture is widely used in:

* homelabs
* self-hosted services
* remote-access gateways
* zero-trust deployments
* security-sensitive workloads

The important security implication is that the application container is not network-isolated from the VPN container. They share:

* interfaces
* routes
* localhost (`127.0.0.1`)
* listening sockets
* DNS configuration
* Tailscale interfaces
* firewall behavior

This means:

* localhost is shared
* DNS leaks become possible if improperly configured
* published ports belong to the VPN namespace owner
* all traffic routing decisions occur in the VPN namespace
* if the VPN fails and no kill-switch exists, traffic leakage may occur

A VPN sidecar is therefore not merely a privacy feature. It is:

* an egress gateway
* a namespace boundary
* a routing policy
* a DNS policy
* a firewall policy
* an observability boundary

---

## Red-Team Practical: Demonstrate Shared VPN Namespace

Create a Docker Compose deployment with:

* a Tailscale VPN container
* an isolated application container sharing its namespace

### docker-compose.yml

```yaml
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

    volumes:
      - ./tailscale-state:/var/lib/tailscale

    environment:
      - TS_STATE_DIR=/var/lib/tailscale

    command: tailscaled

    restart: unless-stopped

  isolated:
    image: nicolaka/netshoot
    container_name: isolated

    network_mode: "service:tailscale"

    depends_on:
      - tailscale

    command: sleep infinity
```

Start the environment.

```bash
docker compose up -d
```

Authenticate Tailscale.

```bash
docker exec tailscale tailscale up
```

Or with an auth key.

```bash
docker exec tailscale tailscale up --authkey=tskey-auth-xxxxxxxx
```

Verify Tailscale connectivity.

```bash
docker exec tailscale tailscale status
```

Observation:

* Tailscale IP assigned
* online status
* peers visible

---

## Red-Team Practical: Demonstrate Shared Interfaces

Inspect networking from the isolated container.

```bash
docker exec -it isolated sh
```

Inside the isolated container.

```bash
ip addr
ip route
cat /etc/resolv.conf
```

Observe:

* `tailscale0` interface exists
* routes belong to the shared namespace
* DNS configuration is inherited from the VPN namespace

Example output snippet.

```text
tailscale0:
inet 100.x.x.x/32
```

Compare with the VPN container.

```bash
docker exec tailscale ip addr
docker exec tailscale ip route
docker exec tailscale cat /etc/resolv.conf
```

Observation:

* both containers display the same interfaces and routes

Attacker perspective: the isolated container does not possess an independent network namespace.

---

## Red-Team Practical: Demonstrate Shared Localhost

Enter the VPN container.

```bash
docker exec -it tailscale sh
```

Install netcat if necessary.

```sh
apk update
apk add netcat-openbsd
```

Start a localhost listener.

```sh
nc -l -p 9090
```

In another terminal, enter the isolated container.

```bash
docker exec -it isolated sh
```

Send traffic to localhost.

```sh
echo "shared localhost test" | nc 127.0.0.1 9090
```

Observation:

* traffic sent from `isolated` reaches the listener running in `tailscale`

Attacker perspective: localhost is shared between containers using the same network namespace.

---

## Blue-Team Practical: Understand Namespace-Owned Port Publishing

Remove previous containers.

```bash
docker compose down
```

Modify the Tailscale service to publish a port.

```yaml
ports:
  - "127.0.0.1:9090:9090"
```

Restart the environment.

```bash
docker compose up -d
```

Inside the isolated container, start a listener.

```bash
docker exec -it isolated sh
```

Inside:

```sh
nc -l -p 9090
```

From the Docker host:

```bash
nc -vz 127.0.0.1 9090
```

Observation:

* the connection succeeds

Important observation:

* the listening process exists inside `isolated`
* but the published port belongs to the namespace owner (`tailscale`)

Defensive interpretation: published ports must be configured on the namespace-owning VPN container.

---

## Blue-Team Practical: Demonstrate Traffic Traversal

Install packet-capture tools in the VPN container.

```bash
docker exec -it tailscale sh
```

```sh
apk update
apk add tcpdump
```

Start packet capture.

```sh
tcpdump -i any
```

In another terminal, generate traffic from the isolated container.

```bash
docker exec -it isolated sh
```

```sh
curl google.com
ping 1.1.1.1
```

Observation:

* traffic generated by `isolated` appears inside the VPN container capture

Defensive interpretation: all traffic from namespace-sharing containers traverses the VPN namespace.

---

## Blue-Team Practical: Demonstrate Kill-Switch Behavior

Stop the VPN container.

```bash
docker stop tailscale
```

Attempt outbound connectivity from the isolated container.

```bash
docker exec -it isolated sh
```

```sh
curl google.com
```

Observation:

* connectivity fails immediately

Defensive interpretation: the isolated workload cannot bypass the VPN because it does not own a separate network namespace.

---

## Blue-Team Practical: Exit Nodes and Full-Tunnel VPN Routing

By default, Tailscale provides encrypted mesh connectivity but does not automatically route all internet traffic through another node.

To force all traffic through a remote Tailscale node, configure an exit node.

On another Tailscale-connected system:

```bash
sudo tailscale up --advertise-exit-node
```

Inside the VPN container:

```bash
docker exec tailscale tailscale up --exit-node=<TAILSCALE-IP>
```

Verify public IP from the isolated container.

```bash
docker exec -it isolated sh
```

```sh
curl ifconfig.me
```

Observation:

* the public IP corresponds to the exit node

Defensive interpretation: exit nodes transform Tailscale from a mesh overlay into a full-tunnel VPN egress architecture.

---

## Defensive Considerations

Defenders should verify:

* DNS routing behavior
* tunnel-failure behavior
* route ownership
* namespace sharing implications
* localhost exposure
* published port exposure
* packet visibility
* firewall enforcement

Useful verification commands:

```bash
docker exec tailscale ip route
docker exec tailscale cat /etc/resolv.conf

docker exec isolated ip route
docker exec isolated cat /etc/resolv.conf

docker inspect isolated | grep IPAddress
```

A container using:

```yaml
network_mode: "service:tailscale"
```

typically does not possess its own independent Docker IP address.

---

## Cleanup

```bash
docker compose down
```

---
