# Chapter 5: Docker Network Types and Security Impact

## Theory

Docker networking is driver-based. The common built-in drivers include `bridge`, `host`, `none`, `overlay`, `macvlan`, and `ipvlan`. There is also an important operational pattern where one container shares another container’s network namespace using `--network container:<name>` or Compose `network_mode: "service:<name>"`. Each model changes reachability, discoverability, isolation, and monitoring.

The security mistake is to treat every Docker network as equivalent. A default bridge is a convenience network. A user-defined bridge is a better single-host application trust zone. Host networking removes network namespace isolation. The none network can eliminate network egress for jobs that do not need it. Overlay networks create distributed trust zones across Docker hosts. Macvlan and ipvlan place containers closer to the physical or virtual network. Namespace sharing makes multiple containers share interfaces, routes, DNS behavior, and localhost.

A security review of Docker networking should always ask which network driver is used, which containers share the network, which services are published, which names are discoverable, and whether the network choice weakens or strengthens the intended trust boundary.

**Mechanism:** Docker network drivers decide which Linux or Docker networking primitives are created for a container. A driver may place the container behind a bridge and NAT, share the host network namespace, remove external networking, create an overlay across Docker nodes, or attach the container directly to the LAN. The chosen driver changes addressing, routing, DNS behavior, port publishing, and where enforcement can happen.

**Security consequence:** network driver choice is a security architecture decision. The same image can have very different risk depending on whether it runs on a user-defined bridge, host networking, a shared VPN namespace, or a macvlan network with direct LAN reachability.

## 5.1 Default Bridge

### Theory

The default bridge is used when a container is started without an explicit network. It is convenient for quick testing, but it is not the best design for production-style segmentation. Name-based service discovery is not as clean as on user-defined bridge networks. The security issue is not that the default bridge is always dangerous. The issue is that it is often unplanned, and unplanned networks become accidental trust zones.

**Mechanism:** containers on the default bridge are attached to Docker's default `bridge` network and receive addresses from that shared subnet. They can often reach each other by IP, but name-based discovery is limited compared with user-defined bridges.

**Security consequence:** the default bridge tends to collect unrelated workloads. Even when names do not resolve, IP-level reachability can still give a compromised container a path to services that were never intentionally grouped with it.

### Red-Team Practical

Start a default-bridge web container.

```bash
docker rm -f default-web 2>/dev/null || true

docker run -d \
  --name default-web \
  nginx:alpine
```

Start a client on the default bridge.

```bash
docker run -it --rm curlimages/curl sh
```

Inside the client, try name-based discovery.

```sh
curl -I http://default-web || true
exit
```

Get the IP of the web container and test by IP.

```bash
WEB_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' default-web)
echo "$WEB_IP"
docker run --rm curlimages/curl -I "http://$WEB_IP"
```

Observation: name-based access on the default bridge may fail while IP-based access succeeds.

Attacker perspective: IP reachability and DNS discoverability are different. Even without name resolution, an attacker may still reach services if they can discover IPs.

### Blue-Team Practical

Inspect the default bridge.

```bash
docker network inspect bridge
ip addr show docker0
```

List containers connected to it.

```bash
docker network inspect bridge | jq '.[0].Containers'
```

Defensive interpretation: defenders should avoid using the default bridge as a shared dumping ground for unrelated workloads.

Cleanup.

```bash
docker rm -f default-web
```

## 5.2 User-Defined Bridge

### Theory

A user-defined bridge is usually the right default for standalone Docker and Docker Compose. It allows the defender to create intentional single-host trust zones such as `frontend`, `backend`, `database`, `monitoring`, and `admin`. Containers on the same user-defined bridge can typically resolve each other by name through Docker’s embedded DNS. The remaining risk is that same-network access is usually broad. User-defined networks reduce blast radius between networks, but they do not automatically implement microsegmentation inside a network.

**Mechanism:** a user-defined bridge creates a separate Docker-managed bridge, address pool, and DNS scope. Containers attached to that network can resolve other containers on the same network by container name, service name, or configured aliases.

**Security consequence:** user-defined bridges are useful trust zones, not complete internal firewalls. They reduce cross-network discovery and reachability, but every container on the same network should still be treated as mutually reachable unless additional controls exist.

### Red-Team Practical

Create a user-defined network and start a web container.

```bash
docker network create app-net

docker run -d \
  --name app-web \
  --network app-net \
  nginx:alpine
```

Start an attacker-style client.

```bash
docker run -it --rm \
  --name app-client \
  --network app-net \
  nicolaka/netshoot
```

Inside the client.

```sh
getent hosts app-web
curl -I http://app-web
exit
```

Observation: `app-client` resolves `app-web` by name and reach it over HTTP.

Attacker perspective: Docker DNS makes service discovery easy inside a user-defined bridge.

### Blue-Team Practical

Inspect the network.

```bash
docker network inspect app-net
```

Create a separate network and show that network membership matters.

```bash
docker network create isolated-net

docker run -d \
  --name isolated-web \
  --network isolated-net \
  nginx:alpine
```

From a container on `app-net`, try to reach `isolated-web`.

```bash
docker run --rm \
  --network app-net \
  nicolaka/netshoot \
  sh -c 'getent hosts isolated-web || true; curl -I --max-time 3 http://isolated-web || true'
```

Observation: a container on `app-net` does not resolve or reach `isolated-web` on `isolated-net` unless it also joins that network.

Defensive interpretation: segmentation reduces both reachability and discoverability.

Cleanup.

```bash
docker rm -f app-web isolated-web
docker network rm app-net isolated-net
```

## 5.3 Host Network

### Theory

Host networking removes the container’s separate network namespace and makes the container share the host’s network stack. This can be useful for performance, monitoring, service discovery, or network appliances, but it is a major reduction in isolation. A host-networked container can see host interfaces, bind directly to host ports, and may reach services that were bound only to localhost on the host.

**Mechanism:** with host networking, Docker does not create a separate container network namespace. The container process uses the host's interfaces, routes, listening sockets, and local address space directly.

**Security consequence:** host networking collapses an important boundary. Port conflicts become host port conflicts, localhost is host localhost, and network observation from inside the container becomes observation of the host network stack.

### Red-Team Practical

Compare bridge networking with host networking.

```bash
docker run --rm nicolaka/netshoot ip addr
docker run --rm --network host nicolaka/netshoot ip addr
```

Check listening sockets from host-network mode.

```bash
docker run --rm --network host nicolaka/netshoot ss -tulpen
```

Observation: the host-networked container sees host interfaces and host listening sockets rather than an isolated container bridge view.

Attacker perspective: a host-networked container gets a much better view of host networking.

### Blue-Team Practical

Find host-networked containers.

```bash
docker ps -q | xargs -r docker inspect \
  --format '{{.Name}} {{.HostConfig.NetworkMode}}' | grep host || true
```

Review Compose files.

```bash
grep -R "network_mode:.*host" . || true
```

Defensive interpretation: host networking should be visible in configuration review and runtime inventory.

## 5.4 None Network

### Theory

The none network gives a container a network namespace with only loopback. This is a strong and simple control for workloads that do not need network access. The caveat is that no network does not mean no risk. A container with no network may still be dangerous if it has sensitive host mounts, secrets, the Docker socket, privileged mode, or excessive capabilities.

**Mechanism:** `--network none` creates or uses a network namespace with only `lo` and no Docker-managed external interface, default route, or bridge attachment.

**Security consequence:** removing the network removes a large class of egress and lateral movement paths. It does not compensate for unsafe mounts, secrets, capabilities, or runtime privileges.

### Red-Team Practical

Run a no-network container and try outbound access.

```bash
docker run --rm --network none alpine ip addr
docker run --rm --network none alpine ip route
docker run --rm --network none alpine sh -c 'wget -T 3 -qO- http://example.com || true'
```

Observation: the container has only loopback and does not have a usable default route for internet egress.

Attacker perspective: egress disappears when the network is removed.

### Blue-Team Practical

Identify workloads that do not need networking and run them with `--network none`.

```bash
docker run --rm \
  --network none \
  alpine \
  sh -c 'echo "offline job"; date'
```

In Compose, the same concept looks like this.

```yaml
services:
  offline-job:
    image: alpine
    command: sh -c 'echo offline job && date'
    network_mode: "none"
```

Defensive interpretation: the strongest egress policy is no egress at all when the workload does not require network access.

## 5.5 Overlay Networks

### Theory

Overlay networks allow containers or services on different Docker hosts to communicate over a logical network. They are most commonly associated with Docker Swarm. An overlay network creates a distributed trust zone. A container compromised on one Docker host may be able to reach services on another host if they share the same overlay network. Overlay encryption may be available when configured, but defenders should verify how the network was created and how traffic is protected.

**Mechanism:** Docker overlay networking uses encapsulation to carry container traffic across multiple Docker hosts. The overlay abstracts the underlying host network so services can communicate as if they were on the same logical network.

**Security consequence:** an overlay network expands the blast radius from one host to a distributed trust zone. Exposure and segmentation reviews must include every participating node, service, and published routing path.

### Red-Team Practical

This lab requires a Swarm-capable environment. On a single test host, initialize Swarm.

```bash
docker swarm init
```

Create an overlay network and services.

```bash
docker network create -d overlay app-overlay

docker service create \
  --name overlay-web \
  --network app-overlay \
  nginx:alpine

docker service create \
  --name overlay-client \
  --network app-overlay \
  nicolaka/netshoot \
  sleep infinity
```

Exec into the client task.

```bash
CLIENT_ID=$(docker ps --filter name=overlay-client -q | head -n 1)
docker exec -it "$CLIENT_ID" sh
```

Inside.

```sh
getent hosts overlay-web
curl -I http://overlay-web
exit
```

Attacker perspective: service discovery and reachability can span Docker hosts in a real multi-node Swarm.

### Blue-Team Practical

Inspect the overlay.

```bash
docker network inspect app-overlay
docker service inspect overlay-web
docker service ps overlay-web
```

Review which nodes participate, whether encryption is enabled, and whether published services use routing mesh. Defensive interpretation: an overlay network is a distributed trust zone.

Cleanup.

```bash
docker service rm overlay-web overlay-client
docker network rm app-overlay
docker swarm leave --force
```

## 5.6 Macvlan and IPvlan

### Theory

Macvlan and ipvlan are used when containers need to appear more directly on the physical or virtual network. Macvlan can give containers their own MAC addresses. IPvlan gives operators direct control over IP addressing while changing Layer 2 behavior compared with macvlan. These drivers are useful for legacy applications, network appliances, and environments where NAT is undesirable. The security tradeoff is that containers move closer to the LAN, so host firewall assumptions, network inventory, NAC, switch policy, VLANs, and external ACLs become more important.

**Mechanism:** macvlan and ipvlan attach containers closer to the parent network interface instead of hiding them behind Docker's default bridge and NAT model. Depending on the mode, containers may appear as distinct Layer 2 or Layer 3 endpoints on the surrounding network.

**Security consequence:** these drivers move enforcement responsibility outward. The container may need to be visible to network inventory, switch policy, VLAN ACLs, cloud routing, and external monitoring instead of relying on host-local Docker bridge assumptions.

### Practical: Safe Local Macvlan Lab

This lab creates a fake LAN on the host instead of using the real physical or public interface. A Linux bridge acts like a small switch. A network namespace acts like an external client. The Docker macvlan network attaches the container to that fake LAN.

Topology.

```text
mv-client namespace 10.90.0.10/24
        |
      veth
        |
br-mvlab Linux bridge
        |
Docker macvlan container 10.90.0.50/24
```

Clean up any previous run.

```bash
docker rm -f macvlan-web 2>/dev/null || true
docker network rm macvlan-lab 2>/dev/null || true
sudo ip netns del mv-client 2>/dev/null || true
sudo ip link del br-mvlab 2>/dev/null || true
```

Create the fake LAN and external client.

```bash
sudo ip link add br-mvlab type bridge
sudo ip link set br-mvlab up

sudo ip netns add mv-client
sudo ip link add mv-host type veth peer name mv-ns
sudo ip link set mv-host master br-mvlab
sudo ip link set mv-host up
sudo ip link set mv-ns netns mv-client

sudo ip netns exec mv-client ip addr add 10.90.0.10/24 dev mv-ns
sudo ip netns exec mv-client ip link set lo up
sudo ip netns exec mv-client ip link set mv-ns up
```

Create the macvlan network on the fake bridge.

```bash
docker network create -d macvlan \
  --subnet=10.90.0.0/24 \
  -o parent=br-mvlab \
  macvlan-lab
```

Run a container with a fake-LAN IP.

```bash
docker run -d \
  --name macvlan-web \
  --network macvlan-lab \
  --ip 10.90.0.50 \
  nginx:alpine
```

Test from the external-client namespace.

```bash
sudo ip netns exec mv-client curl -I --max-time 5 http://10.90.0.50
```

Expected result: the namespace receives an HTTP response from nginx. The important point is that the client connects directly to the container IP. No Docker host port is published.

Inspect what the client learned at Layer 2.

```bash
sudo ip netns exec mv-client ip neigh show
docker inspect macvlan-web \
  --format '{{range .NetworkSettings.Networks}}IP={{.IPAddress}} MAC={{.MacAddress}}{{end}}'
```

Expected result: the client neighbor table shows `10.90.0.50` with a MAC address, and `docker inspect` shows the same MAC for the macvlan container. This demonstrates the macvlan model: the container appears as a distinct Layer 2 endpoint on the attached network.

### Firewall Observation

Macvlan traffic does not look like a normal Docker bridge published-port path. There is no `-p` mapping, no Docker DNAT to a bridge container, and the traffic does not rely on the `DOCKER-USER` chain in the way Chapter 2's bridge-port example does.

Zero counters, make a request, and inspect the Docker chains.

```bash
sudo iptables -Z DOCKER-USER 2>/dev/null || true
sudo ip netns exec mv-client curl -I --max-time 5 http://10.90.0.50
sudo iptables -L DOCKER-USER -n -v --line-numbers 2>/dev/null || true
sudo iptables -t nat -L DOCKER -n -v --line-numbers 2>/dev/null || true
```

Expected result: on a normal Linux Docker host, `DOCKER-USER` and Docker NAT counters should not explain this request. Defensive interpretation: with macvlan, exposure is controlled more by IP reachability, parent-interface policy, upstream ACLs, and network inventory than by Docker port publishing.

Attacker perspective: the container is reached as a network endpoint, not as `host:published-port`.

Blue-team perspective: inventory and firewall review must include the container IP itself.

Cleanup.

```bash
docker rm -f macvlan-web
docker network rm macvlan-lab
sudo ip netns del mv-client
sudo ip link del br-mvlab
```


## 5.7 IPvlan Networks

### Theory

IPvlan deserves separate treatment because it solves a different operational problem than macvlan. Macvlan gives containers distinct MAC addresses on the parent network. IPvlan keeps container traffic behind the parent interface's MAC address and separates endpoints primarily by IP. That difference matters in virtualized, cloud, hosting, and switch-controlled environments where multiple source MAC addresses on one port may be blocked, rate-limited, or treated as suspicious.

IPvlan has two modes that are useful to explain clearly.

In IPvlan L2 mode, containers live in the same Layer 2 network as the parent interface. They use IP addresses from the attached network, but they do not create additional visible MAC addresses. This can be useful where the upstream network allows extra IP addresses but does not allow extra MAC addresses.

In IPvlan L3 mode, containers live behind the host as routed IP endpoints. The upstream network must know how to route the container subnet back to the Docker host. This is closer to a routed container network than a LAN attachment. It is often the cleaner design when the provider or network team can route a dedicated prefix to the host.

**Mechanism:** ipvlan attaches containers to a parent interface while sharing the parent interface's MAC address. L2 mode makes container IPs participate on the parent Layer 2 network. L3 mode requires routing for the container subnet and avoids depending on broadcast or neighbor discovery in the same way.

**Security consequence:** ipvlan can bypass the mental model of "container is hidden behind Docker bridge NAT." If a container receives a routable address, it may be reachable directly. Published Docker ports may no longer be the only exposure path. The host firewall, upstream ACLs, provider firewall, route tables, and monitoring all need to be reviewed together.

### Public-Interface Framing

Using macvlan or ipvlan on a public interface is possible only when the addressing and upstream network support it. Do not move the host's only public IP address into a container. The host still needs its own management address, default route, and control-plane reachability.

For macvlan on a public interface, the provider or switch must allow multiple MAC addresses on the same virtual or physical port. Many VPS and cloud networks do not allow this, so macvlan may fail even when the Docker configuration is correct.

For ipvlan L2 on a public interface, multiple container IPs can share the host interface MAC. This may work in environments where extra MAC addresses are blocked but extra IP addresses are permitted. The provider must still allow those additional IP addresses to be used on that interface.

For ipvlan L3 on a public interface, the clean model is a routed public prefix. The provider routes a subnet to the Docker host, and the host routes traffic to containers through the ipvlan network. This is usually better than trying to make individual containers pretend to be normal hosts on a public LAN.

Defensive framing: a public macvlan or ipvlan container should be treated as internet-facing infrastructure, not as an internal Docker workload. Inventory, patching, service binding, upstream firewall rules, logging, and incident response all need to include the container IPs.

### Practical: Safe Local IPvlan L2 Lab

This lab mirrors the macvlan lab, but uses ipvlan L2. It uses a fake veth link instead of the real public interface. The host-side veth is the ipvlan parent, and the namespace-side veth is the external client.

Topology.

```text
iv-client namespace 10.91.0.10/24
        |
     veth pair
        |
iv-parent host interface
        |
Docker ipvlan L2 container 10.91.0.50/24
```

Clean up any previous run.

```bash
docker rm -f ipvlan-l2-web 2>/dev/null || true
docker network rm ipvlan-l2-lab 2>/dev/null || true
sudo ip netns del iv-client 2>/dev/null || true
sudo ip link del iv-parent 2>/dev/null || true
```

Create the fake parent link and external client.

```bash
sudo ip netns add iv-client
sudo ip link add iv-parent type veth peer name iv-ns
sudo ip link set iv-ns netns iv-client
sudo ip link set iv-parent up

sudo ip netns exec iv-client ip addr add 10.91.0.10/24 dev iv-ns
sudo ip netns exec iv-client ip link set lo up
sudo ip netns exec iv-client ip link set iv-ns up
```

Create the ipvlan L2 network on the host-side veth parent.

```bash
docker network create -d ipvlan \
  --subnet=10.91.0.0/24 \
  -o parent=iv-parent \
  -o ipvlan_mode=l2 \
  ipvlan-l2-lab
```

Run a container with a fake-LAN IP.

```bash
docker run -d \
  --name ipvlan-l2-web \
  --network ipvlan-l2-lab \
  --ip 10.91.0.50 \
  nginx:alpine
```

Test from the external-client namespace.

```bash
sudo ip netns exec iv-client curl -I --max-time 5 http://10.91.0.50
```

Expected result: the namespace receives an HTTP response from nginx. Again, no Docker host port is published.

Inspect the Layer 2 difference from macvlan.

```bash
sudo ip netns exec iv-client ip neigh show
ip -brief link show iv-parent
docker inspect ipvlan-l2-web \
  --format '{{range .NetworkSettings.Networks}}IP={{.IPAddress}} MAC={{.MacAddress}}{{end}}'
```

Expected result: the client neighbor table shows `10.91.0.50` using the `iv-parent` MAC, while Docker does not report a separate container MAC in the same way as the macvlan example. This demonstrates the ipvlan L2 model: the container has its own IP, but traffic is associated with the parent interface MAC.

Troubleshooting note: if `ip addr` inside the container shows `LOWERLAYERDOWN`, inspect the parent path before assuming ipvlan is broken.

```bash
ip -brief link show iv-parent
sudo ip netns exec iv-client ip -brief link
sudo ip netns exec iv-client ip neigh show
sudo ip netns exec iv-client curl -I --max-time 5 http://10.91.0.50
```

The parent interface should be `UP` and should show `LOWER_UP`. If the parent was created after the Docker network, is down, or was deleted/recreated after the Docker network was created, the ipvlan interface may report a lower-layer state that looks alarming and reachability may fail. The decisive test is reachability from `iv-client` to `10.91.0.50` plus the neighbor-table observation. If reachability fails, recreate the lab in this order: namespace, veth pair, parent up, namespace address up, Docker ipvlan network, container.

### Firewall Observation

Repeat the same counter check.

```bash
sudo iptables -Z DOCKER-USER 2>/dev/null || true
sudo ip netns exec iv-client curl -I --max-time 5 http://10.91.0.50
sudo iptables -L DOCKER-USER -n -v --line-numbers 2>/dev/null || true
sudo iptables -t nat -L DOCKER -n -v --line-numbers 2>/dev/null || true
```

Expected result: this direct ipvlan L2 request is not explained by Docker bridge DNAT or the normal published-port path. Defensive interpretation: ipvlan L2 shifts the review toward direct IP reachability, parent-interface policy, upstream routing, and upstream firewall controls.

Cleanup.

```bash
docker rm -f ipvlan-l2-web
docker network rm ipvlan-l2-lab
sudo ip netns del iv-client
sudo ip link del iv-parent
```

### IPvlan L3 Framing

IPvlan L3 is still worth discussing, but it is better as a routed-design explanation unless the classroom environment has an explicit routed prefix.

In a real IPvlan L3 design, the upstream network has a route like this.

```text
<container-routed-prefix> via <docker-host-parent-ip>
```

Docker then creates an ipvlan L3 network using that routed prefix.

```bash
docker network create -d ipvlan \
  --subnet=<container-routed-prefix> \
  -o parent=<parent-interface> \
  -o ipvlan_mode=l3 \
  ipvlan-l3-lab
```

Expected interpretation: if routing is correct, the container is reachable by its own IP without Docker port publishing. If routing is missing, the container may work locally but fail from the outside because return traffic has no valid path.

### Red-Team Practical

Map the difference between published-port exposure and direct-IP exposure.

```bash
docker ps
docker network inspect ipvlan-l2-lab 2>/dev/null || true
docker network inspect ipvlan-l3-lab 2>/dev/null || true
```

Attacker perspective: if a container has a routable IP, scanning the host's published ports is not enough. The container address itself becomes part of the attack surface.

### Blue-Team Practical

Build a short exposure review for every ipvlan deployment.

```bash
docker network ls
docker network inspect <ipvlan-network>
ip route
ip neigh
```

Review whether the container IPs are public or private, whether the upstream route is intentional, which firewall enforces ingress, whether egress is logged, and whether asset inventory includes those addresses. Defensive interpretation: ipvlan is not insecure by default, but it is easy to under-monitor because traffic may not look like ordinary Docker bridge traffic.


## 5.7 IPv6, Direct Routing, and Gateway Modes

### Theory

Docker network security is often taught as an IPv4 NAT story, but modern environments are not always NAT-only. IPv6, direct routing, and bridge gateway modes can change how container addresses are reached and how published ports behave. This matters because many firewall reviews are written with IPv4 assumptions: host port equals exposure, NAT hides container addresses, and bridge subnets are not externally routable. Those assumptions can fail when IPv6 is enabled or when operators deliberately route to container subnets.

The defensive question is not simply whether a port is published. The question is whether any network path can reach the container address or container service. That includes host port publishing, direct routing to container subnets, IPv6 reachability, trusted host interfaces, overlay networks, macvlan, ipvlan, and cloud routing.

A professional review should explicitly ask whether IPv6 is enabled, whether Docker is managing `ip6tables`, whether container subnets are routed, whether direct routing is intentional, and whether security controls cover both IPv4 and IPv6.

**Mechanism:** IPv6 and routed container subnets can remove the implicit hiding effect that teams often associate with IPv4 NAT. A container address may be reachable directly if routing and firewall policy allow it, even when the mental model assumes all access must come through a host-published IPv4 port.

**Security consequence:** exposure review must cover both address families and both published-port and direct-routing paths. A service that appears protected in IPv4 may still be reachable over IPv6 or through routed container networks.

### Red-Team Practical

Inspect whether IPv6 appears in Docker configuration and container networking.

```bash
docker info | egrep -i 'IPv6|ip6tables' || true
ip -6 addr || true
sudo ip6tables -S 2>/dev/null | head || true

docker run --rm nicolaka/netshoot sh -c 'ip -6 addr || true; ip -6 route || true'
```

Observation: many basic labs will show little or no IPv6 container routing. If IPv6 is enabled, treat that as an additional attack surface and repeat exposure tests for IPv6 paths.

### Blue-Team Practical

Review daemon configuration for IPv6 and firewall behavior.

```bash
sudo cat /etc/docker/daemon.json 2>/dev/null || true
docker network inspect bridge | jq '.[0].EnableIPv6, .[0].IPAM.Config'
```

Observation: IPv6 can be classified as disabled, enabled but unrouted, or enabled and reachable. Defensive interpretation: a Docker network review is incomplete until IPv4 and IPv6 exposure are both understood.

## 5.8 Rootless Docker Networking

### Theory

Rootless Docker reduces the risk of a rootful Docker daemon by allowing the daemon and containers to run without normal root privileges. That is valuable, but it changes networking. Port publishing, privileged ports, packet filtering, and namespace behavior may differ from a rootful Docker Engine host. Rootless Docker should not be presented as a simple replacement for firewall policy. It changes the trust model and the operational constraints.

The professional question is what risk rootless Docker reduces and what risks remain. It may reduce daemon-level host compromise impact, but compromised workloads can still perform network discovery, call out to attacker infrastructure, abuse credentials, reach internal services, and leak data if the network design allows it.

**Mechanism:** rootless Docker cannot use the same privileged host networking operations as rootful Docker. It commonly relies on user-mode networking components and different port-forwarding behavior.

**Security consequence:** rootless mode changes daemon privilege risk, but it does not remove the need for network design. Reachability, DNS behavior, egress paths, and published ports still need explicit review.

### Practical: Identify Whether Docker Is Rootless

```bash
docker info | grep -i rootless || true
ps aux | grep -E 'dockerd|rootlesskit|slirp4netns' | grep -v grep || true
```

Observation: rootful lab hosts usually show no rootless mode. If rootless components appear, expect Chapter 2 firewall mechanics to differ.

Defensive interpretation: rootless Docker belongs in an enterprise security discussion, but it does not eliminate the need for intentional reachability, discoverability, egress, and attribution controls.

---
