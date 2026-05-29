# Iptables and Basics of the Linux Kernel Firewall

> Generated from visible slide content only. Presenter notes are intentionally excluded.

## Table of contents
- [Slide 1: Iptables and Basics of the Linux Kernel Firewall](#slide-1-iptables-and-basics-of-the-linux-kernel-firewall)
- [Slide 2: Agenda](#slide-2-agenda)
- [Slide 3: Learning outcomes](#slide-3-learning-outcomes)
- [Slide 4: Recap: container networking mental model](#slide-4-recap-container-networking-mental-model)
- [Slide 5: Why Linux firewalling matters for containers](#slide-5-why-linux-firewalling-matters-for-containers)
- [Slide 6: Netfilter: the kernel firewall framework](#slide-6-netfilter-the-kernel-firewall-framework)
- [Slide 7: Tooling overview](#slide-7-tooling-overview)
- [Slide 8: Cisco analogy: ACLs + NAT + stateful inspection](#slide-8-cisco-analogy-acls-nat-stateful-inspection)
- [Slide 9: Cisco analogy: ACLs + NAT + stateful inspection](#slide-9-cisco-analogy-acls-nat-stateful-inspection)
- [Slide 10: The most important concept: packet traversal](#slide-10-the-most-important-concept-packet-traversal)
- [Slide 11: Common Traffic Types and Their Firewall Paths](#slide-11-common-traffic-types-and-their-firewall-paths)
- [Slide 12: INPUT vs FORWARD](#slide-12-input-vs-forward)
- [Slide 13: INPUT vs FORWARD](#slide-13-input-vs-forward)
- [Slide 14: iptables tables](#slide-14-iptables-tables)
- [Slide 15: Chains: where rules are evaluated](#slide-15-chains-where-rules-are-evaluated)
- [Slide 16: Basic iptables rule syntax](#slide-16-basic-iptables-rule-syntax)
- [Slide 17: Common match conditions](#slide-17-common-match-conditions)
- [Slide 18: Common targets/actions](#slide-18-common-targets-actions)
- [Slide 19: Rule evaluation order](#slide-19-rule-evaluation-order)
- [Slide 20: Use iptables-save for visibility](#slide-20-use-iptables-save-for-visibility)
- [Slide 21: Default policies](#slide-21-default-policies)
- [Slide 22: Stateful firewalling with conntrack](#slide-22-stateful-firewalling-with-conntrack)
- [Slide 23: conntrack states](#slide-23-conntrack-states)
- [Slide 24: Basic stateful host firewall pattern](#slide-24-basic-stateful-host-firewall-pattern)
- [Slide 25: Inspecting conntrack](#slide-25-inspecting-conntrack)
- [Slide 26: NAT in Linux](#slide-26-nat-in-linux)
- [Slide 27: NAT flow overview](#slide-27-nat-flow-overview)
- [Slide 28: SNAT and MASQUERADE](#slide-28-snat-and-masquerade)
- [Slide 29: DNAT for port forwarding](#slide-29-dnat-for-port-forwarding)
- [Slide 30: DNAT for port forwarding](#slide-30-dnat-for-port-forwarding)
- [Slide 31: Docker and iptables](#slide-31-docker-and-iptables)
- [Slide 32: Docker chain idea](#slide-32-docker-chain-idea)
- [Slide 33: Practical lab topology](#slide-33-practical-lab-topology)
- [Slide 34: Lab step 1: create app network and web container](#slide-34-lab-step-1-create-app-network-and-web-container)
- [Slide 35: Lab step 2: verify application and container IP](#slide-35-lab-step-2-verify-application-and-container-ip)
- [Slide 36: Lab step 3: inspect Docker-generated NAT](#slide-36-lab-step-3-inspect-docker-generated-nat)
- [Slide 37: Lab step 4: prove the packet path with tcpdump](#slide-37-lab-step-4-prove-the-packet-path-with-tcpdump)
- [Slide 38: Lab step 5: inspect conntrack](#slide-38-lab-step-5-inspect-conntrack)
- [Slide 39: Lab step 6: add a simple DOCKER-USER policy](#slide-39-lab-step-6-add-a-simple-docker-user-policy)
- [Slide 40: Lab safety: remove test rules](#slide-40-lab-safety-remove-test-rules)
- [Slide 41: Troubleshooting workflow: published port](#slide-41-troubleshooting-workflow-published-port)
- [Slide 42: Scenario: rule in the wrong chain](#slide-42-scenario-rule-in-the-wrong-chain)
- [Slide 43: Scenario: rule in the wrong chain](#slide-43-scenario-rule-in-the-wrong-chain)
- [Slide 44: Scenario: NAT is fine, application is broken](#slide-44-scenario-nat-is-fine-application-is-broken)
- [Slide 45: Scenario: container has no Internet access](#slide-45-scenario-container-has-no-internet-access)
- [Slide 46: Logging packets safely](#slide-46-logging-packets-safely)
- [Slide 47: nftables reality check](#slide-47-nftables-reality-check)
- [Slide 48: Inspect nftables](#slide-48-inspect-nftables)
- [Slide 49: Security best practices](#slide-49-security-best-practices)
- [Slide 50: Security best practices](#slide-50-security-best-practices)
- [Slide 51: Lab cleanup](#slide-51-lab-cleanup)
- [Slide 52: Command cheat sheet: iptables](#slide-52-command-cheat-sheet-iptables)
- [Slide 53: Command cheat sheet: troubleshooting](#slide-53-command-cheat-sheet-troubleshooting)
- [Slide 54: Final mental model](#slide-54-final-mental-model)
- [Slide 55: Untitled](#slide-55-untitled)
- [Slide 56: Questions?](#slide-56-questions)

## Slide 1: Iptables and Basics of the Linux Kernel Firewall

> Visual element(s): 1 image/diagram object(s) on this slide.

Netfilter, packet traversal, stateful firewalling, NAT and Docker traffic flows

Practical lab: continue the Docker bridge example with nginx, published ports and firewall rules

---

## Slide 2: Agenda

A firewall-focused continuation of the container networking introduction

- Kernel firewall architecture: Netfilter, iptables and nftables

- Packet traversal: INPUT, FORWARD, OUTPUT, PREROUTING, POSTROUTING

- Filtering: chains, tables, rule order and default policies

- Stateful firewalling: conntrack states and session tracking

- NAT: SNAT, MASQUERADE, DNAT and Docker port publishing

- Practical lab: secure and troubleshoot a Docker nginx service

---

## Slide 3: Learning outcomes

What you should be able to do after this deck

- Draw the Linux firewall packet path from memory

- Know which chain to inspect for host, forwarded and container traffic

- Read basic iptables rules and iptables-save output

- Build a simple stateful host firewall

- Explain how Docker uses NAT and FORWARD rules

- Troubleshoot a published container port using iptables, conntrack and tcpdump

---

## Slide 4: Recap: container networking mental model

host routing+ firewall/NAT

Containernamespace

Linuxbridge

physicalNIC

veth

This deck zooms into the host routing + firewall/NAT box.

---

## Slide 5: Why Linux firewalling matters for containers

A container problem is often a Linux firewall path problem

- Containers use Linux networking primitives, not a separate network stack

- Docker creates firewall and NAT rules automatically

- Published ports are implemented through kernel packet traversal

- Outbound container Internet access commonly depends on MASQUERADE

- Troubleshooting requires knowing where packets hit firewall chains

---

## Slide 6: Netfilter: the kernel firewall framework

Do not think of iptables as the firewall engine itself

- Netfilter is built into the Linux kernel packet path

- It provides packet filtering, NAT, mangling and connection tracking

- iptables is a user-space tool that configures Netfilter rules

- nftables is the modern framework that is replacing iptables

- The kernel processes packets; tools only configure the rules

---

## Slide 7: Tooling overview

| Tool | Role | Typical use |
| --- | --- | --- |
| iptables | classic rule management | filtering and NAT examples |
| iptables-save | full ruleset export | best visibility tool for iptables |
| nft | modern ruleset management | nftables-based systems |
| conntrack | session/NAT state inspection | stateful troubleshooting |
| tcpdump | packet evidence | prove path before/after firewall |

---

## Slide 8: Cisco analogy: ACLs + NAT + stateful inspection

| Cisco/networking concept | Linux concept | Important note |
| --- | --- | --- |
| ACL entry | iptables rule | Rule order matters |
| Interface direction | chain/hook position | INPUT/FORWARD/OUTPUT paths |
| NAT overload/PAT | MASQUERADE/SNAT | Often in POSTROUTING |
| Static port forward | DNAT | Often in PREROUTING |
| Stateful firewall | conntrack | Return traffic matched by state |

---

## Slide 9: Cisco analogy: ACLs + NAT + stateful inspection

> Visual element(s): 1 image/diagram object(s) on this slide.

---

## Slide 10: The most important concept: packet traversal

Local delivery

Locally generated

INPUT

OUTPUT

PREROUTING

RoutingDecision

FORWARD

POSTROUTING

Routed traffic

Most mistakes happen because the rule is correct — but placed in the wrong chain.

---

## Slide 11: Common Traffic Types and Their Firewall Paths

| Traffic type | Example | Primary chain/path |
| --- | --- | --- |
| Traffic to the Linux host | SSH to host | INPUT |
| Traffic routed through the host | container → Internet | FORWARD + POSTROUTING |
| Traffic generated by the host | host curl example.com | OUTPUT + POSTROUTING |
| Traffic to a published container port | client → host:8080 → container:80 | PREROUTING DNAT + FORWARD |

Docker traffic is usually forwarded traffic, not local host INPUT traffic.

---

## Slide 12: INPUT vs FORWARD

INPUTpacket is destinedfor the Linux host

FORWARDpacket is routedthrough the Linux host

Example: SSH to host → INPUT

Example: published Docker port → FORWARD

---

## Slide 13: INPUT vs FORWARD

> Visual element(s): 1 image/diagram object(s) on this slide.

---

## Slide 14: iptables tables

| Table | Purpose | Common chains |
| --- | --- | --- |
| filter | allow/drop/reject traffic | INPUT, FORWARD, OUTPUT |
| nat | source/destination NAT | PREROUTING, OUTPUT, POSTROUTING |
| mangle | mark/modify packets | multiple hooks |
| raw | conntrack exemptions | PREROUTING, OUTPUT |

---

## Slide 15: Chains: where rules are evaluated

Chains are packet path checkpoints

- PREROUTING: before the routing decision, common place for DNAT

- INPUT: packets delivered locally to the Linux host

- FORWARD: routed packets passing through the Linux host

- OUTPUT: packets generated by local processes

- POSTROUTING: after routing decision, common place for SNAT/MASQUERADE

---

## Slide 16: Basic iptables rule syntax

```bash
Terminal
# allow SSH to the host
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
# drop ICMP to the host
sudo iptables -A INPUT -p icmp -j DROP
# list rules with counters
sudo iptables -L -n -v
```

Rule = chain + match conditions + target/action

---

## Slide 17: Common match conditions

| Match | Example | Meaning |
| --- | --- | --- |
| Protocol | -p tcp | match TCP packets |
| Source | -s 10.0.0.0/24 | match source network |
| Destination | -d 192.168.1.10 | match destination IP |
| Port | --dport 443 | match destination TCP/UDP port |
| Interface | -i eth0 / -o docker0 | match ingress or egress interface |
| State | -m conntrack --ctstate ESTABLISHED | match connection state |

---

## Slide 18: Common targets/actions

| Target | Meaning | Typical use |
| --- | --- | --- |
| ACCEPT | allow the packet | permit required traffic |
| DROP | silently discard | stealthier blocking |
| REJECT | discard and notify sender | clear troubleshooting behavior |
| LOG | log and continue | visibility before decision |
| DNAT | change destination | published ports |
| MASQUERADE | dynamic source NAT | container egress |

---

## Slide 19: Rule evaluation order

This is similar to ACL processing, but across multiple chains

- Rules are evaluated top-down inside a chain

- The first terminating match usually decides the packet outcome

- Specific exceptions should appear before broad rules

- Default policy applies if no rule matches

- Rule counters help prove which rule is being hit

---

## Slide 20: Use iptables-save for visibility

```bash
Terminal
$ sudo iptables-save
*filter
:INPUT ACCEPT [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
COMMIT
```

---

## Slide 21: Default policies

```bash
Terminal
# default deny for host inbound traffic
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT
# but first allow existing sessions and management access
```

Warning: setting INPUT DROP remotely without allowing SSH can lock you out.

---

## Slide 22: Stateful firewalling with conntrack

Stateful inspection is the firewall memory

- conntrack tracks flows and connection state

- Stateful rules allow return traffic without reverse static rules

- Common states: NEW, ESTABLISHED, RELATED, INVALID

- NAT depends on conntrack to map return traffic

- conntrack is central to Docker NAT behavior

---

## Slide 23: conntrack states

| State | Meaning | Typical firewall action |
| --- | --- | --- |
| NEW | new connection attempt | allow only if explicitly permitted |
| ESTABLISHED | part of an existing flow | allow |
| RELATED | related to an existing flow | allow when needed |
| INVALID | cannot be identified or malformed state | drop/log |

---

## Slide 24: Basic stateful host firewall pattern

```bash
Terminal
# allow loopback
sudo iptables -A INPUT -i lo -j ACCEPT
# allow return traffic
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# allow SSH
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
# default deny
sudo iptables -P INPUT DROP
```

---

## Slide 25: Inspecting conntrack

```bash
Terminal
$ sudo conntrack -L
tcp 6 431999 ESTABLISHED src=10.0.0.50 dst=10.0.0.20 sport=51522 dport=22 ...
$ sudo conntrack -L -p tcp --dport 80
$ sudo conntrack -E
# conntrack -E streams events live
```

When NAT is involved, conntrack shows the before/after tuple.

---

## Slide 26: NAT in Linux

NAT is packet rewriting plus state tracking

- NAT rules live in the nat table

- DNAT commonly happens before routing in PREROUTING

- SNAT/MASQUERADE commonly happens after routing in POSTROUTING

- NAT is applied mainly to the first packet of a connection

- conntrack applies the remembered translation to the rest of the flow

---

## Slide 27: NAT flow overview

Where translations normally occur

packet enters

PREROUTINGDNAT

routing

FORWARD

POSTROUTINGSNAT

packet exits

DNAT changes where the packet goes. SNAT changes who the packet appears to come from.

---

## Slide 28: SNAT and MASQUERADE

```bash
Terminal
# static source NAT
sudo iptables -t nat -A POSTROUTING -s 172.18.0.0/16 -o eth0 \
  -j SNAT --to-source 10.0.0.20
# dynamic source NAT
sudo iptables -t nat -A POSTROUTING -s 172.18.0.0/16 -o eth0 \
  -j MASQUERADE
```

Docker commonly uses MASQUERADE for container egress.

---

## Slide 29: DNAT for port forwarding

```bash
Terminal
# forward host TCP/8080 to container TCP/80
sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 \
  -j DNAT --to-destination 172.18.0.2:80
# allow forwarded traffic
sudo iptables -A FORWARD -p tcp -d 172.18.0.2 --dport 80 -j ACCEPT
```

Port publishing is a DNAT + forwarding problem.

---

## Slide 30: DNAT for port forwarding

> Visual element(s): 1 image/diagram object(s) on this slide.

---

## Slide 31: Docker and iptables

Docker is not bypassing Linux firewalling — it is using it

- Docker creates custom chains for its bridge networks and published ports

- Docker modifies nat and filter tables automatically

- DOCKER chain commonly contains DNAT rules for published ports

- DOCKER-USER is intended for administrator-defined policy

- Do not edit Docker-managed chains blindly

---

## Slide 32: Docker chain idea

PREROUTING

DOCKERnat chain

DNAT tocontainer

FORWARD

container

Exact chains may vary by Docker version, iptables backend and distribution.

---

## Slide 33: Practical lab topology

Linux hostiptables/NAT

external clientor host curl

Docker bridgeapp-net

web containernginx :80

We continue the Docker bridge example: app-net + nginx + published port 8080.

---

## Slide 34: Lab step 1: create app network and web container

```bash
Terminal
$ docker network create app-net
$ docker run -d --name web --network app-net -p 8080:80 nginx:alpine
$ docker ps --format 'table {{.Names}}\t{{.Ports}}\t{{.Networks}}'
NAMES   PORTS                  NETWORKS
web     0.0.0.0:8080->80/tcp   app-net
```

---

## Slide 35: Lab step 2: verify application and container IP

```bash
Terminal
$ curl -I http://127.0.0.1:8080
HTTP/1.1 200 OK
$ docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' web
172.18.0.2
$ docker exec web ss -ltnp
LISTEN 0.0.0.0:80
```

---

## Slide 36: Lab step 3: inspect Docker-generated NAT

```bash
Terminal
$ sudo iptables-save | grep -E '8080|DNAT|MASQUERADE|DOCKER'
-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
-A DOCKER ! -i br-xxxx -p tcp -m tcp --dport 8080 \
    -j DNAT --to-destination 172.18.0.2:80
-A POSTROUTING -s 172.18.0.0/16 ! -o br-xxxx -j MASQUERADE
```

This single output shows both inbound DNAT and outbound MASQUERADE.

---

## Slide 37: Lab step 4: prove the packet path with tcpdump

```bash
Terminal
# terminal 1: capture host port
$ sudo tcpdump -ni any tcp port 8080
# terminal 2: capture container port on Docker bridge
$ sudo tcpdump -ni br-xxxx tcp port 80
# terminal 3: generate traffic
$ curl http://127.0.0.1:8080
```

Before DNAT: host:8080. After DNAT: container:80.

---

## Slide 38: Lab step 5: inspect conntrack

```bash
Terminal
$ sudo conntrack -L -p tcp | grep 172.18.0.2
tcp 6 431999 ESTABLISHED src=127.0.0.1 dst=127.0.0.1 sport=51522 dport=8080
    src=172.18.0.2 dst=172.18.0.1 sport=80 dport=51522
# exact output depends on source path and Docker settings
```

conntrack shows the remembered flow state used for return traffic.

---

## Slide 39: Lab step 6: add a simple DOCKER-USER policy

```bash
Terminal
# example: allow one source, then drop other forwarded container ingress
sudo iptables -I DOCKER-USER 1 -s 10.0.0.50 -p tcp --dport 80 -j ACCEPT
sudo iptables -A DOCKER-USER -p tcp --dport 80 -j DROP
# inspect counters
sudo iptables -L DOCKER-USER -n -v --line-numbers
```

Use DOCKER-USER for custom Docker filtering instead of editing Docker-managed chains.

---

## Slide 40: Lab safety: remove test rules

```bash
Terminal
$ sudo iptables -L DOCKER-USER -n -v --line-numbers
# delete by line number, starting with the highest number
$ sudo iptables -D DOCKER-USER 2
$ sudo iptables -D DOCKER-USER 1
# or flush only if you know this is a lab host
$ sudo iptables -F DOCKER-USER
```

Never casually flush production firewall rules.

---

## Slide 41: Troubleshooting workflow: published port

docker ps

ss in container

is port published?

is app listening?

iptables nat

iptables filter

is DNAT present?

is FORWARD allowed?

conntrack

tcpdump

is state created?

where does packet stop?

---

## Slide 42: Scenario: rule in the wrong chain

```bash
Terminal
# admin tries to block published container port
sudo iptables -A INPUT -p tcp --dport 8080 -j DROP
# but Docker published port may still work
$ curl http://host-ip:8080
HTTP/1.1 200 OK
! published container traffic is commonly FORWARD after DNAT
```

Correct-looking rule, wrong path.

---

## Slide 43: Scenario: rule in the wrong chain

> Visual element(s): 1 image/diagram object(s) on this slide.

---

## Slide 44: Scenario: NAT is fine, application is broken

```bash
Terminal
$ docker ps
web  0.0.0.0:8080->80/tcp
$ curl http://127.0.0.1:8080
curl: Empty reply from server
$ docker exec web ss -ltnp
# no listener on :80
```

Do not blame iptables until you prove the service is listening.

---

## Slide 45: Scenario: container has no Internet access

```bash
Terminal
$ docker exec client ping -c 2 8.8.8.8
100% packet loss
# check route in container
$ docker exec client ip route
# check host forwarding and NAT
$ sysctl net.ipv4.ip_forward
$ iptables-save | grep MASQUERADE
```

Likely areas: container default route, host forwarding, FORWARD chain or POSTROUTING MASQUERADE.

---

## Slide 46: Logging packets safely

```bash
Terminal
# log before dropping
sudo iptables -A INPUT -p tcp --dport 8080 -j LOG --log-prefix 'FW DROP 8080: '
sudo iptables -A INPUT -p tcp --dport 8080 -j DROP
# view logs
sudo journalctl -k -f
sudo dmesg -w
```

Be careful: logging high-volume traffic can overwhelm logs.

---

## Slide 47: nftables reality check

Learn the packet model first; syntax can change

- Many modern distributions use nftables under the hood

- iptables commands may use the iptables-nft compatibility layer

- iptables-save may still show rules even when nftables backend is active

- nft list ruleset shows the native nftables view

- Concepts remain the same: hooks, chains, rules, state, NAT

---

## Slide 48: Inspect nftables

```bash
Terminal
$ sudo nft list ruleset
table ip nat {
  chain PREROUTING { type nat hook prerouting priority dstnat; }
  chain POSTROUTING { type nat hook postrouting priority srcnat; }
}
$ iptables --version
iptables v1.8.x (nf_tables)
```

---

## Slide 49: Security best practices

Firewalling is both control and visibility

- Start with a clear policy: what should be reachable, from where?

- Use stateful rules for return traffic

- Expose only required Docker ports

- Bind published ports to 127.0.0.1 when external access is not needed

- Use DOCKER-USER for administrator Docker firewall policy

- Always test with tcpdump and rule counters

---

## Slide 50: Security best practices

> Visual element(s): 1 image/diagram object(s) on this slide.

Firewalling is both control and visibility

---

## Slide 51: Lab cleanup

```bash
Terminal
$ docker rm -f web client
$ docker network rm app-net
# remove only lab rules from DOCKER-USER
$ sudo iptables -L DOCKER-USER -n -v --line-numbers
$ sudo iptables -D DOCKER-USER <line-number>
# verify
$ docker ps -a
$ docker network ls
```

---

## Slide 52: Command cheat sheet: iptables

```bash
Cheat sheet
iptables -L -n -v
iptables -S
iptables-save
iptables -t nat -L -n -v
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -t nat -A POSTROUTING -s 172.18.0.0/16 -j MASQUERADE
iptables -L DOCKER-USER -n -v --line-numbers
```

---

## Slide 53: Command cheat sheet: troubleshooting

```bash
Cheat sheet
docker ps
docker network inspect app-net
docker exec web ss -ltnp
conntrack -L
conntrack -E
tcpdump -ni any tcp port 8080
tcpdump -ni br-xxxx tcp port 80
ip route get <destination>
bridge fdb show
journalctl -k -f
```

---

## Slide 54: Final mental model

Container traffic is usually not special.It is Linux forwarded traffic with extra automation.

Outbound

FORWARD → POSTROUTING MASQUERADE

Inbound published port

PREROUTING DNAT → FORWARD → container

Host service

INPUT

---

## Slide 55: Untitled

> Visual element(s): 1 image/diagram object(s) on this slide.

---

## Slide 56: Questions?

Packet traversal + conntrack + NAT = Linux firewall troubleshooting

Follow the packet. Check the correct chain. Prove it with counters and captures.

---
