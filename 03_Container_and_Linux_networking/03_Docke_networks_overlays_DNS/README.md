# Docker Networks, Overlays, DNS

This module moves from Linux primitives and firewalling into Docker's actual networking model.

The goal is to explain how Docker groups workloads, how service discovery works, how multi-host overlays fit in, and where the security-relevant choices live.

## Where This Fits In The Day

Module 1 explained the Linux building blocks.

Module 2 explained how Docker uses the Linux firewall.

This module explains the Docker layer on top:

- network drivers
- user-defined networks
- Compose networks
- overlays
- service discovery
- DNS behavior

This is where architecture decisions become security decisions.

## Learning Objectives

By the end of this lecture, participants should be able to:

- explain the purpose of the main Docker network drivers
- describe why user-defined bridge networks are usually better than the default bridge
- explain how Docker DNS and service discovery work on custom networks
- understand when overlay networks are appropriate and what they expose operationally
- design small Docker network topologies with clearer security boundaries

## Suggested Timing

This module works well as a 55-60 minute lecture:

| Time | Topic |
| --- | --- |
| 0-10 min | Docker network drivers and the high-level model |
| 10-22 min | Bridge networking and Compose networks |
| 22-32 min | DNS, service names, aliases, and multi-network containers |
| 32-42 min | Overlay networks and multi-host concerns |
| 42-60 min | Security-focused design patterns and best practices |

## The Main Docker Network Drivers

On Linux, Docker's built-in drivers include:

- `bridge`
- `host`
- `none`
- `overlay`
- `ipvlan`
- `macvlan`

For this course, the important idea is not to memorize all of them equally.

It is to understand what security tradeoff each one makes.

## `bridge`

This is the normal single-host answer.

Use it when containers on the same Docker host should communicate while remaining separated from unrelated containers and from the outside world unless explicitly published.

## `host`

This removes network isolation between container and host.

Use it rarely and intentionally.

If you need it, you should be able to explain exactly why.

## `none`

This disconnects the container from normal networking.

It can be useful for very constrained or special-purpose workloads.

## `overlay`

This connects workloads across multiple Docker daemons and is strongly associated with Swarm mode.

It is powerful and operationally sensitive.

## `ipvlan` and `macvlan`

These expose containers more directly into the surrounding network.

They can be useful, but they push more responsibility to the operator and reduce some of the isolation and simplicity teams expect from bridge networking.

For this course, treat them as specialized tools, not defaults.

## The Most Important Production Default: User-Defined Bridge Networks

Docker's docs are very clear here:

- the default `bridge` network is a legacy detail and is not recommended for production
- user-defined bridge networks are superior

The reasons are exactly the reasons security teams should care about:

- automatic DNS resolution by container name
- better isolation
- easier attachment and detachment
- clearer scoping of which containers can talk to each other

That last point is the big one.

If everything lands on the same default bridge, unrelated services can communicate too easily.

## What A User-Defined Bridge Gives You

At a practical level, a user-defined bridge network gives you:

- a distinct subnet
- a Linux bridge managed by Docker
- isolated membership
- embedded DNS for name resolution
- controlled port publishing behavior

This makes it much easier to build meaningful zones such as:

- edge network
- application network
- data network

That pattern is far better than a single flat network.

## Compose Networks

Docker Compose creates a network for an application by default.

Each service joins that network and can be reached by service name.

That is very convenient, but it also encourages people to leave everything on one flat app network.

A better pattern is usually to define named networks explicitly.

For example:

```yaml
services:
  proxy:
    networks:
      - edge
      - app

  backend:
    networks:
      - app
      - data

  db:
    networks:
      - data

networks:
  edge: {}
  app: {}
  data:
    internal: true
```

That is a much clearer design:

- `proxy` is the only edge-facing service
- `backend` can talk both upstream and downstream
- `db` is not on the edge-facing network

## The `internal` Flag

Compose supports `internal: true` for networks.

This creates an externally isolated network.

That is a very strong and teachable pattern for:

- databases
- caches
- internal APIs
- message brokers
- supporting services that should never have direct outward reachability

Important nuance:

- `internal` helps isolate that network from external connectivity
- it is not a substitute for least-privilege service placement

If you attach too many things to the internal network, you still have unnecessary east-west exposure inside it.

## Service Discovery And DNS

This is where participants often build the wrong mental model.

Docker's DNS behavior depends on the network type.

Docker documents that:

- containers on the default bridge get a copy of the host's `resolv.conf`
- containers on custom networks use Docker's embedded DNS server
- the embedded DNS server forwards external lookups to the DNS servers configured on the host

That has very practical consequences.

On a user-defined network, containers can typically resolve peers by:

- container name
- service name in Compose
- network alias if configured

This is one reason user-defined networks are so much better operationally than the default bridge.

## Security Meaning Of Embedded DNS

The embedded DNS server is a convenience feature, but it also affects security design.

Good:

- service naming becomes stable
- you can avoid hard-coded IPs
- networks become easier to reason about

Risk:

- people start treating name resolution as a trust mechanism
- "it resolves" gets confused with "it is authorized"

DNS is discovery.

It is not access control.

## Multi-Network Containers

Docker allows containers to connect to more than one network.

This is powerful and dangerous.

A multi-homed container becomes a bridge between trust zones at the application layer.

That is fine when intentional.

For example:

- an Nginx reverse proxy between edge and app networks
- a backend API between app and data networks

It is dangerous when casual.

For example:

- debugging containers attached everywhere
- monitoring containers with unnecessary access to every network
- admin tools that quietly bypass intended segmentation

Docker also documents that the default gateway may change depending on which networks are attached, and `gw-priority` can influence that choice.

That matters for both reachability and security.

## Overlay Networks

Overlay networks let containers on different Docker hosts communicate through a distributed virtual network.

Docker documents several important realities:

- overlay networks require Docker hosts to be part of a Swarm
- common required ports include `2377/tcp`, `4789/udp`, and `7946/tcp/udp`
- services or containers can only communicate across networks they are both attached to
- encryption can be enabled for overlay traffic

This is where participants should slow down.

Overlay networks are not just "bridge networks, but bigger."

They expand:

- operational complexity
- failure domains
- firewall requirements between nodes
- blast radius if node trust is weak

## Overlay Security Themes

Teach these explicitly:

## 1. Open Only The Ports You Need Between Overlay Nodes

Required control-plane and overlay ports should be limited to the participating nodes.

Do not leave them broadly reachable across the environment.

## 2. Encryption Matters

Docker documents that overlay traffic can communicate securely when encryption is enabled.

If the network path between nodes is not fully trusted, that matters.

## 3. Multi-Host Means Bigger Blast Radius

A misattached service or compromised node can now affect communication across hosts, not just inside one machine.

## 4. Overlay Does Not Replace Segmentation

An overlay is a connectivity mechanism.

It is not a trust model.

You still need network boundaries, service boundaries, and exposure boundaries.

## Host Networking

This deserves a short but strong warning.

The host network driver removes network isolation between container and host.

That can be useful for:

- high-performance edge cases
- unusual port requirements

But it comes with obvious security costs:

- host and container port namespace overlap
- no bridge isolation
- fewer natural chokepoints for filtering
- easier accidental exposure

For most application workloads, this should not be the default answer.

## Security-Focused Design Patterns

## Pattern 1: Edge / App / Data Segmentation

This is the most important one.

Use separate networks for:

- reverse proxy or gateway
- application services
- databases and caches

Only multi-home the components that truly need it.

## Pattern 2: Publish Only The Edge

If a service is not supposed to be reached directly by users or external systems, do not publish it.

Expose:

- proxy
- public API

Do not expose:

- databases
- Redis
- admin consoles
- backends that should sit behind the proxy

## Pattern 3: Use Service Names, Not Hard-Coded IPs

On user-defined networks and Compose networks, DNS-based service discovery is the right operational model.

Hard-coded IPs create brittle systems and encourage admins to reason about the wrong layer.

## Pattern 4: Prefer User-Defined Bridge Networks Over The Default Bridge

This is one of Docker's clearest operational recommendations and also one of the best security defaults.

## Pattern 5: Be Careful With Multi-Network Attachments

Every extra network interface is a trust decision.

## Pattern 6: Use `internal` Where It Matches The Design

This is especially useful for backend-only and data-plane networks.

## Good Lecture Demo Ideas

A short practical sequence can make this module much more concrete:

```bash
docker network create frontend-net
docker network create --internal backend-net
docker run -d --name api --network backend-net nginx
docker run -d --name proxy --network frontend-net nginx
docker network connect backend-net proxy
docker network inspect frontend-net
docker network inspect backend-net
```

Then explain:

- which container is on which network
- which one acts as the boundary-crossing component
- why `backend-net` being internal does not mean "everyone on it is safe"

If using Compose, show service names resolving across the right network and failing across the wrong one.

## Best Practices

1. Prefer user-defined bridge networks over the default bridge.
2. Segment by trust boundary, not by convenience.
3. Publish only edge-facing services.
4. Use `internal` for backend-only networks where appropriate.
5. Avoid `host` mode unless there is a clear technical reason.
6. Treat every extra network attachment as added attack surface.
7. Use service discovery by name, but do not confuse name resolution with authorization.
8. Open overlay ports only between participating nodes and review whether encryption is enabled.

## Key Takeaways

- Docker's network driver choice affects both reachability and security.
- User-defined bridges are the normal secure default for single-host application stacks.
- Compose networks are convenient, but they should be designed deliberately.
- Docker DNS helps discovery, not trust.
- Overlay networks solve multi-host connectivity, but they also widen operational and security responsibility.

## References

- Docker networking overview: <https://docs.docker.com/engine/network/>
- Docker network drivers overview: <https://docs.docker.com/engine/network/drivers/>
- Docker bridge network driver: <https://docs.docker.com/engine/network/drivers/bridge/>
- Docker overlay network driver: <https://docs.docker.com/engine/network/drivers/overlay/>
- Docker Swarm service networking: <https://docs.docker.com/engine/swarm/networking/>
- Docker Compose networking how-to: <https://docs.docker.com/compose/how-tos/networking/>
- Docker Compose networks reference: <https://docs.docker.com/reference/compose-file/networks/>
