# Iptables And Basics Of The Linux Kernel Firewall

This module explains the machinery Docker depends on when it exposes ports, forwards traffic, and isolates bridge networks on Linux.

It is one of the most important security modules in the whole course because container networking problems often turn out to be firewall and forwarding problems.

## Where This Fits In The Day

Module 1 explained the packet path.

This module explains where Linux can filter, translate, and forward that traffic.

The red line is:

- packets have to go somewhere
- Linux decides what is allowed
- Docker programs part of that decision automatically
- security teams must understand where to safely add their own rules

## Learning Objectives

By the end of this lecture, participants should be able to:

- explain the netfilter hook model at a practical level
- distinguish the roles of filtering, forwarding, and NAT
- explain how Docker uses iptables on Linux bridge and overlay networking
- understand what the `DOCKER-USER` chain is for
- explain the current relationship between Docker, iptables, and nftables
- apply safe security controls without breaking Docker networking

## Suggested Timing

This module works well as a 50-55 minute lecture:

| Time | Topic |
| --- | --- |
| 0-10 min | Netfilter hook model and why it matters |
| 10-22 min | Iptables basics: tables, chains, state, NAT |
| 22-35 min | How Docker programs iptables |
| 35-45 min | Safe places to add security rules |
| 45-55 min | Common mistakes, nftables reality, best practices |

## The Practical Netfilter Model

For this course, participants do not need every historical detail.

They need this mental model:

```text
Inbound to host:      PREROUTING -> INPUT
Host-generated:       OUTPUT -> POSTROUTING
Forwarded traffic:    PREROUTING -> FORWARD -> POSTROUTING
```

Docker cares deeply about the **forwarded traffic** path because container traffic on bridge networks is usually forwarded through the host.

That is the first big mindset shift.

Many people think only about `INPUT`.

For Docker networking, `FORWARD` is often where the interesting security behavior lives.

## What Iptables Actually Does

`iptables` is the userspace tool used to configure Linux packet filtering and NAT rules in the legacy xtables model.

At a practical level, teams mostly care about:

- **filtering** traffic
- **allowing or denying forwarding**
- **doing destination NAT** for published ports
- **doing source NAT / masquerading** for outbound traffic

That is enough to understand most Docker behavior.

## The Tables Worth Teaching

For a security-focused container course, the most useful tables are:

## `filter`

This is where allow and deny logic commonly lives.

Conceptually:

- `INPUT` is for traffic addressed to the host
- `OUTPUT` is for traffic sent by the host
- `FORWARD` is for traffic passing through the host

For Docker networking, `FORWARD` matters a lot.

## `nat`

This is where address translation happens.

Docker uses it for:

- port publishing
- masquerading outbound bridge traffic

This is why a published port can forward traffic to a container even though the container has a different IP.

## Connection Tracking Matters

Modern container traffic is rarely filtered statelessly.

Linux connection tracking keeps state about flows.

That is what makes rules like:

- allow `ESTABLISHED,RELATED`
- permit new inbound only on selected ports

practical and efficient.

It also matters when Docker rewrites addresses.

By the time a packet reaches certain filter points, the destination may already have been translated.

That detail becomes important when you want to match the original destination IP or port.

## Docker And Iptables

On Linux, Docker creates iptables rules for bridge networks and uses them to implement:

- network isolation
- forwarding
- port publishing
- NAT and masquerading

Docker documents several custom chains it creates in the `filter` table:

- `DOCKER-USER`
- `DOCKER-FORWARD`
- `DOCKER`
- `DOCKER-BRIDGE`
- `DOCKER-INTERNAL`
- `DOCKER-CT`
- `DOCKER-INGRESS`

And in the `nat` table it creates a `DOCKER` chain for:

- masquerading
- port mapping

That means Docker is not merely using the network stack.

It is actively programming the firewall.

## The Most Important Chain: `DOCKER-USER`

If participants remember only one chain name, make it this one.

Docker documents `DOCKER-USER` as the place for user-defined rules that should run before Docker's own forwarding logic.

This is where administrators can safely add policy such as:

- source allowlists
- source deny rules
- inter-interface restrictions
- logging for suspicious forwarded traffic

Do **not** teach people to edit Docker-managed chains directly.

That is fragile and likely to be overwritten by Docker.

## Why Appending To `FORWARD` Often Does Not Work The Way People Expect

Docker adds jumps from the `FORWARD` chain to its own chains.

Packets accepted or rejected inside those Docker chains may never hit rules simply appended later to `FORWARD`.

That is why Docker explicitly tells users to place custom policies in `DOCKER-USER`.

This is one of the most common reasons people think:

"my firewall rule is correct, but Docker is ignoring it."

Docker is not ignoring it.

The packet likely never reached the rule where they put it.

## Published Ports And DNAT

When you run something like:

```bash
docker run -p 8080:80 nginx
```

Docker creates NAT and filter rules so that traffic arriving at the host on port `8080` is forwarded to port `80` in the container.

Security meaning:

- a published port is a firewall rule plus NAT rule
- it is not a lightweight convenience feature
- opening a port in Docker is a security event

## Matching Original Destinations

Docker documents an easy-to-miss detail:

by the time traffic reaches `DOCKER-USER`, it has already gone through DNAT.

So, if you want to filter based on the original destination IP or port, you need connection-tracking matches such as `--ctorigdst` and `--ctorigdstport`.

That is a subtle but very practical point for real access-control rules.

Docker also notes that heavy use of those conntrack matches can have a performance cost.

## IP Forwarding And Docker

Docker requires IP forwarding for ordinary bridge networking features.

When running with iptables, Docker may enable forwarding on the host and set the default policy of the `FORWARD` chain to `DROP`.

That behavior surprises many administrators.

Security meaning:

- the host is now forwarding traffic
- forwarding needs deliberate policy
- if the host also has multiple physical interfaces, this can affect routing behavior beyond containers

Docker explicitly recommends a drop-oriented forwarding policy unless the host is intentionally acting as a router.

## Safe Practical Examples

These are good lecture examples because they match real-world needs.

## Restrict A Published Port To A Source IP

Docker's documented pattern is to insert a rule at the top of `DOCKER-USER`:

```bash
iptables -I DOCKER-USER -i ext_if ! -s 192.0.2.2 -j DROP
```

That expresses an extremely useful operational idea:

publish the service, but restrict who can reach it.

## Allow Forwarding Between Specific Interfaces

If you truly need forwarding between host interfaces:

```bash
iptables -I DOCKER-USER -i src_if -o dst_if -j ACCEPT
```

That makes the point that forwarding is not a side effect to ignore.

It is a routing and firewall decision.

## Two Very Important Official Warnings

## 1. Do Not Disable Docker Firewalling Unless You Really Know What You Are Doing

Docker documents daemon settings such as `iptables=false` and `ip6tables=false`.

It also warns that this is not appropriate for most users and is likely to break container networking.

Worse, if you disable Docker firewalling without replacing it correctly:

- bridge containers may lose normal NAT behavior
- ports may become reachable from the local network in ways you did not expect

This is not a hardening trick.

For most teams it is a foot-gun.

## 2. Docker And UFW Are Not Friends

Docker explicitly documents that `ufw` and Docker are incompatible in an important way.

Why:

- Docker routes published-port traffic in the `nat` table
- that traffic is diverted before it reaches the `INPUT` and `OUTPUT` chains used by `ufw`

Operational meaning:

- teams often think `ufw allow` and `ufw deny` are protecting published container services
- in reality, Docker may expose the service before those `ufw` chains ever see the traffic

This mistake shows up constantly in real environments.

## Docker And Nftables In 2026

There is an important current-state detail participants should hear:

- Docker still defaults to iptables-based firewalling on Linux
- Docker added an **experimental** nftables backend in Docker Engine 29.0.0
- Docker's docs state that overlay-network rules have not yet migrated, so nftables backend cannot be enabled in Swarm mode

This is exactly the kind of detail that matters in modern operations.

It means:

- iptables knowledge is still operationally relevant
- nftables knowledge is increasingly important
- mixed environments and migrations need care

## The Nftables Transition Story

At a high level:

- `iptables` is the legacy userland interface
- `nftables` is the newer packet-classification framework
- the same netfilter hook infrastructure remains underneath

One critical Docker-specific difference:

- with iptables backend, `DOCKER-USER` exists
- with nftables backend, there is no direct `DOCKER-USER` equivalent chain

Docker's nftables docs recommend using your own separate nftables table and base chains rather than modifying Docker's tables.

## Best Practices For Security Teams

1. Learn the forwarded path, not just the input path.
2. Treat published ports as exposure, not convenience.
3. Put custom filtering in `DOCKER-USER` when using Docker's iptables backend.
4. Do not hand-edit Docker-managed chains.
5. Use source allowlists for sensitive published services.
6. Be careful with IP forwarding on multi-homed hosts.
7. Do not assume `ufw` alone is protecting container-published ports.
8. If evaluating nftables backend, remember the current Docker limitations around Swarm and overlay.

## Good Discussion Prompts

- Which services on our hosts are exposed by Docker rules rather than by host daemons?
- Where are we currently placing our custom firewall rules?
- If a port is published today, who can reach it from the outside?
- Are our teams troubleshooting in `INPUT` when the packet is really in `FORWARD`?
- Do we have any hosts where IP forwarding and multiple NICs create extra risk?

## Key Takeaways

- Docker networking on Linux depends heavily on netfilter, forwarding, and NAT.
- `DOCKER-USER` is the safe place for custom iptables filtering in front of Docker's own rules.
- Published ports are implemented by firewall and NAT rules.
- Docker and `ufw` can produce very misleading security assumptions.
- In 2026, iptables is still central for Docker operations even though nftables is the direction of travel.

## References

- Docker with iptables: <https://docs.docker.com/engine/network/firewall-iptables/>
- Docker with nftables: <https://docs.docker.com/engine/network/firewall-nftables/>
- Docker packet filtering and firewalls: <https://docs.docker.com/engine/network/packet-filtering-firewalls/>
- Docker port publishing and mapping: <https://docs.docker.com/engine/network/port-publishing/>
- netfilter iptables project: <https://www.netfilter.org/projects/iptables/index.html>
- netfilter nftables project: <https://www.netfilter.org/projects/nftables/>
- nftables netfilter hooks overview: <https://wiki.netfilter.org/wiki-nftables/index.php/Netfilter_hooks>
