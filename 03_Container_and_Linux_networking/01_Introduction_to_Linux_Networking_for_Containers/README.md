# Introduction To Linux Networking For Containers

This module gives participants the mental model they need for the rest of Part 03.

The most important idea is simple:

**Docker networking is not magic.**

It is Linux networking primitives assembled in a useful way.

If participants understand those primitives, later topics such as port publishing, firewalling, DNS behavior, network segmentation, and overlay networks become much easier to reason about.

## Where This Fits In The Day

This is the foundation module for the networking part of the course.

The red line for the next four lectures is:

1. understand the packet path
2. understand where Docker inserts itself
3. understand which defaults are convenient but risky
4. understand how to shrink exposure deliberately

This module covers step 1.

## Learning Objectives

By the end of this lecture, participants should be able to:

- explain how a container gets network connectivity on Linux
- describe the roles of network namespaces, veth pairs, Linux bridges, routes, and NAT
- walk through the packet path for container-to-container, container-to-host, container-to-Internet, and host-to-container traffic
- explain why network isolation in Docker is useful but limited
- identify the main security boundaries in single-host container networking

## Suggested Timing

This module works well as a 45-50 minute lecture:

| Time | Topic |
| --- | --- |
| 0-8 min | Why container networking is just Linux networking with automation |
| 8-18 min | The key building blocks: namespaces, interfaces, bridges, routes |
| 18-28 min | Packet flow examples |
| 28-38 min | What isolation really means and where it stops |
| 38-50 min | Practical demo ideas and best-practice recap |

## The Core Mental Model

When Docker starts a normal Linux container on a bridge network, it usually creates or uses:

- a **network namespace** for the container
- a **veth pair**
- a Linux **bridge** on the host
- an IP address and default gateway for the container
- host firewall and NAT rules so traffic can be forwarded correctly

At a high level it looks like this:

```text
container process
-> container network namespace
-> eth0 inside container
-> veth pair
-> Linux bridge on host
-> host routing / netfilter / NAT
-> external network
```

Everything after that is detail.

Important detail, but still detail.

## The Key Linux Building Blocks

## 1. Network Namespaces

A network namespace gives a process its own view of networking.

Inside a container, the process sees:

- its own interfaces
- its own IP addresses
- its own routing table
- its own ARP and neighbor state
- its own DNS configuration
- its own listening sockets

That is why a container can think it owns `eth0` even though many other containers are running on the same host.

The interfaces are not fake.

They are real Linux networking objects, just scoped to that namespace.

Security meaning:

- namespaces give separation
- they do not provide a firewall policy by themselves
- they do not decide who may talk to whom
- they do not prevent the host from seeing or controlling the traffic

## 2. Veth Pairs

A veth pair is like a virtual Ethernet cable.

It comes in two ends:

- one end is moved into the container namespace
- the other stays in the host namespace

Packets entering one end appear on the other.

That is how the container is physically connected to the host-side networking.

Security meaning:

- the host remains on the path
- host policy still matters
- if the host is compromised, container network isolation becomes much less meaningful

## 3. Linux Bridges

Docker bridge networks rely on a Linux software bridge.

The bridge acts like a Layer 2 switch in the host kernel.

It forwards frames between:

- host-side veth interfaces for attached containers
- sometimes other relevant interfaces attached to that bridge

In Docker terms, a bridge network is usually the default answer for "containers on one host should talk to each other."

Security meaning:

- containers on the same bridge can usually talk freely unless extra controls exist
- bridge membership is therefore a security decision, not just a convenience setting

## 4. IP Addressing And Routing

Each container attached to a bridge network gets:

- an IP address in that network
- a subnet
- a default gateway, usually the bridge address

The container does not need to know it is in Docker.

From its point of view it simply has:

- an interface
- an address
- a route to local peers
- a default route for everything else

Security meaning:

- if the route exists and policy allows it, the packet will flow
- attachment to multiple networks means multiple reachable trust zones

## 5. NAT And Masquerading

For ordinary bridge networking, Docker typically uses source NAT or masquerading so containers can reach external networks through the host.

That means outbound traffic from containers often appears to external systems as if it came from the host IP.

Security meaning:

- egress is easy by default
- logging and attribution can become harder
- teams often forget that "container is isolated" does not mean "container cannot talk out"

## The Four Packet Paths Participants Must Understand

## 1. Container To Container On The Same Bridge

This is the easiest path:

```text
container A
-> veth
-> bridge
-> veth
-> container B
```

If both containers are on the same user-defined bridge, they usually communicate directly and can resolve each other by name.

Security implication:

- same-network membership usually means strong east-west reachability
- if unrelated services share a bridge, lateral movement becomes easier

## 2. Container To The Internet

Typical path:

```text
container
-> veth
-> bridge
-> host forwarding path
-> NAT / masquerade
-> host uplink
-> Internet
```

This is why package downloads, API calls, beaconing malware, and data exfiltration are all possible unless you actively restrict egress.

Security implication:

- default outbound access is a major blind spot in many container setups

## 3. Host Or External Client To A Published Port

Typical path:

```text
client
-> host interface
-> prerouting / DNAT
-> forwarding path
-> bridge
-> veth
-> container
```

This path only exists if the port is published or otherwise routed.

Security implication:

- published ports are not just "convenience"
- they are explicit exposure events

## 4. Container To Host Services

The host is often reachable from containers.

That matters because host-local services sometimes include:

- development databases
- admin APIs
- monitoring endpoints
- cloud metadata proxies
- insecure test services

Security implication:

- people often think only about inbound exposure
- host-reachable services can be just as important

## What Isolation Really Means

Container networking gives useful separation.

It does **not** give the kind of separation many people casually assume.

A container on a bridge network is not:

- disconnected from the host
- disconnected from the Internet
- disconnected from peers on the same bridge
- automatically egress filtered
- automatically segmented by sensitivity

It simply has a different namespace and a host-controlled path.

That is a big difference.

## The Security Boundaries To Teach Explicitly

Participants should leave this module understanding at least four boundaries:

## 1. Namespace Boundary

This separates network stacks.

It does not define policy.

## 2. Bridge Membership Boundary

This determines who is on the same L2 segment.

In practice, this is one of the biggest segmentation decisions in Docker networking.

## 3. Host Firewall And Routing Boundary

This determines whether traffic is forwarded, translated, published, or blocked.

## 4. Published-Port Boundary

This is the line where internal container service becomes reachable from host addresses and possibly from the outside world.

## A Useful Practical Story

Imagine a small stack:

- `frontend`
- `backend`
- `postgres`
- `redis`

If they all share one bridge network:

- the frontend can reach the backend
- the backend can reach the database
- the frontend may also be able to reach the database and Redis directly
- malware in one container can probe peers on that same network

That is convenient.

It is also a segmentation failure if those services do not all need direct mutual access.

This is why we will later split networks by function and trust zone.

## Live Demo Ideas

These commands work well in a lecture because they make the invisible visible:

```bash
docker network create demo-net
docker run -d --name web --network demo-net nginx
docker inspect web
docker network inspect demo-net
```

Things to point out live:

- the container got an IP from the bridge subnet
- the network has a gateway
- Docker tracks which endpoints are attached

If you want one more step:

```bash
docker exec web ip addr
docker exec web ip route
docker exec web cat /etc/resolv.conf
```

That gives participants a concrete sense of what the container actually sees.

## Best Practices To Introduce Early

Do not wait until the end of the day to establish these:

1. Treat network attachment as a security decision.
2. Prefer user-defined bridge networks over the default bridge.
3. Publish only the ports that are truly needed.
4. Separate edge-facing services from backend-only services.
5. Assume outbound access exists unless you deliberately restrict it.
6. Document expected flows before adding firewall rules.

## Common Misconceptions To Kill Early

- "Container IP addresses are private, so the service is safe."
- "If it is not published, nobody can reach it."
- "Containers on the same Docker host are already well segmented."
- "Networking problems in Docker are mostly just YAML problems."

All four are dangerous.

## Key Takeaways

- Docker networking is Linux networking with automation and opinionated defaults.
- The fundamental pieces are namespaces, veth pairs, bridges, routes, and NAT.
- Same-network membership usually implies broad reachability.
- Published ports create real exposure.
- Network isolation in containers is useful, but much weaker than many teams assume.

## References

- Docker networking overview: <https://docs.docker.com/engine/network/>
- Docker bridge network driver: <https://docs.docker.com/engine/network/drivers/bridge/>
- Docker port publishing and mapping: <https://docs.docker.com/engine/network/port-publishing/>
- Linux kernel namespaces documentation: <https://docs.kernel.org/admin-guide/namespaces/index.html>
- Linux kernel bridge documentation: <https://docs.kernel.org/networking/bridge.html>
