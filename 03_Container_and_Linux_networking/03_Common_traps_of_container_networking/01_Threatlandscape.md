# Chapter 1: Threat Model and Attacker Mindset

## Theory

Docker networking is often treated as an operational topic, but it is also a security boundary topic. The defender’s mistake is to think only in terms of whether a container is isolated from the host. In practice, many container incidents do not require a kernel escape or a container breakout. A compromised application container may already have the network access needed to discover internal services, reach databases, query Redis, access admin panels, call cloud metadata services, download tooling, open a reverse shell, or exfiltrate data.

The correct security question is not only whether the attacker can escape the container. The first question is what the attacker can reach from inside the container. Reachability determines blast radius. Discoverability determines how quickly the attacker can map the environment. Egress determines whether the attacker can call back to external infrastructure. Attribution determines whether defenders can connect a suspicious connection to a specific container, image, process, and user.

Assume that an attacker has gained code execution inside one low-privileged web container. That attacker can run normal network discovery commands available in many minimal Linux images or can bring tooling if egress allows it. The attacker’s goal is to understand the network, find useful services, pivot to more sensitive tiers, and send data out. The defender’s goal is to make unnecessary paths impossible, necessary paths explicit, and suspicious behavior visible.

**Mechanism:** Docker gives containers their own process, filesystem, and network views, but it does not automatically make them network-blind. A normal bridge-connected container receives an interface, an IP address, a default route, DNS configuration, and usually outbound connectivity through the host. From inside the container, this feels like a small Linux machine on a network.

**Security consequence:** after application compromise, network access often becomes the attacker's first useful capability. The attacker does not need a container escape to enumerate routes, resolve service names, probe host gateways, call internal services, or test egress. The defensive baseline starts by proving what the container can reach before assuming what it cannot reach.

## Red-Team Practical: Think from Inside a Compromised Container

Start a container that represents a compromised application tier.

```bash
docker rm -f threat-web 2>/dev/null || true

docker run -d \
  --name threat-web \
  nicolaka/netshoot \
  sleep infinity
```

Enter the container.

```bash
docker exec -it threat-web sh
```

Run basic discovery.

```sh
whoami
hostname
id
ip addr
ip route
cat /etc/resolv.conf
ss -tulpen
```

Try outbound connectivity.

```sh
curl -I http://example.com
dig example.com
```

Identify the host bridge gateway.

```sh
ip route | awk '/default/ {print $3}'
exit
```

Observation: the container reveals its own interfaces, route table, resolver configuration, and egress behavior.

Attacker perspective: a basic shell is enough to learn the container’s routes, DNS behavior, and egress posture. If the environment is flat, the attacker’s next step is to enumerate internal service names and open ports.

## Blue-Team Practical: Baseline What a Container Can Reach

Inspect the container from the host.

```bash
docker inspect threat-web | jq '.[0].NetworkSettings.Networks'
docker inspect threat-web | jq '.[0].Config.Image, .[0].Config.Cmd'
```

Map the container to a host process.

```bash
docker inspect -f '{{.State.Pid}}' threat-web
```

Check Docker networks.

```bash
docker network ls
docker network inspect bridge
```

Watch traffic on the default bridge while the container makes a request.

```bash
sudo tcpdump -i docker0 -nn
```

In another terminal, run this.

```bash
docker exec threat-web curl -I http://example.com
```

Observation: tcpdump shows traffic on the Docker bridge when the container makes the request. Docker inspection maps the container to a network, IP address, and host process.

Defensive interpretation: defenders need a repeatable way to answer four questions: which container made the connection, which process made it, what destination it reached, and whether that path was expected.

Cleanup.

```bash
docker rm -f threat-web
```
