# Introduction to Linux Networking for Containers

> Generated from visible slide content only. Presenter notes are intentionally excluded.

## Table of contents
- [Slide 1: Combined deck · 50 slides](#slide-1-combined-deck-50-slides)
- [Slide 2: Course storyline](#slide-2-course-storyline)
- [Slide 3: Lab/demo topology](#slide-3-lab-demo-topology)
- [Slide 4: Step 0](#slide-4-step-0)
- [Slide 5: Practical TCP/IP stack](#slide-5-practical-tcp-ip-stack)
- [Slide 6: Layer-to-command mapping](#slide-6-layer-to-command-mapping)
- [Slide 7: IPv4 ranges: public vs private](#slide-7-ipv4-ranges-public-vs-private)
- [Slide 8: Read host addressing](#slide-8-read-host-addressing)
- [Slide 9: Routing: what path will the kernel choose?](#slide-9-routing-what-path-will-the-kernel-choose)
- [Slide 10: DNS and sockets are separate problems](#slide-10-dns-and-sockets-are-separate-problems)
- [Slide 11: Step 0 demo checkpoint](#slide-11-step-0-demo-checkpoint)
- [Slide 12: Step 1](#slide-12-step-1)
- [Slide 13: Linux bridge mental model](#slide-13-linux-bridge-mental-model)
- [Slide 14: Create br0](#slide-14-create-br0)
- [Slide 15: Inspect bridge ports and FDB](#slide-15-inspect-bridge-ports-and-fdb)
- [Slide 16: Cisco CAM vs Linux FDB](#slide-16-cisco-cam-vs-linux-fdb)
- [Slide 17: Step 1 demo checkpoint](#slide-17-step-1-demo-checkpoint)
- [Slide 18: Step 2](#slide-18-step-2)
- [Slide 19: Network namespace mental model](#slide-19-network-namespace-mental-model)
- [Slide 20: veth pair mental model](#slide-20-veth-pair-mental-model)
- [Slide 21: Namespace + veth + bridge topology](#slide-21-namespace-veth-bridge-topology)
- [Slide 22: Build the namespace lab](#slide-22-build-the-namespace-lab)
- [Slide 23: Attach and address](#slide-23-attach-and-address)
- [Slide 24: Test and inspect](#slide-24-test-and-inspect)
- [Slide 25: Step 2 checkpoint](#slide-25-step-2-checkpoint)
- [Slide 26: Step 3](#slide-26-step-3)
- [Slide 27: Docker maps to the primitives](#slide-27-docker-maps-to-the-primitives)
- [Slide 28: Inspect Docker default bridge](#slide-28-inspect-docker-default-bridge)
- [Slide 29: Default bridge topology](#slide-29-default-bridge-topology)
- [Slide 30: Run two containers on default bridge](#slide-30-run-two-containers-on-default-bridge)
- [Slide 31: Create a user-defined bridge](#slide-31-create-a-user-defined-bridge)
- [Slide 32: DNS resolution between containers](#slide-32-dns-resolution-between-containers)
- [Slide 33: Step 3 checkpoint](#slide-33-step-3-checkpoint)
- [Slide 34: Step 4](#slide-34-step-4)
- [Slide 35: Why Docker needs NAT](#slide-35-why-docker-needs-nat)
- [Slide 36: Outbound NAT path](#slide-36-outbound-nat-path)
- [Slide 37: Inspect NAT and conntrack](#slide-37-inspect-nat-and-conntrack)
- [Slide 38: Publish a container port](#slide-38-publish-a-container-port)
- [Slide 39: Inbound published-port path](#slide-39-inbound-published-port-path)
- [Slide 40: Inspect DNAT rules](#slide-40-inspect-dnat-rules)
- [Slide 41: INPUT vs FORWARD](#slide-41-input-vs-forward)
- [Slide 42: Packet capture proves NAT](#slide-42-packet-capture-proves-nat)
- [Slide 43: Step 4 checkpoint](#slide-43-step-4-checkpoint)
- [Slide 44: Step 5](#slide-44-step-5)
- [Slide 45: The main mental model](#slide-45-the-main-mental-model)
- [Slide 46: End-to-end troubleshooting decision tree](#slide-46-end-to-end-troubleshooting-decision-tree)
- [Slide 47: Practical lab: build and verify](#slide-47-practical-lab-build-and-verify)
- [Slide 48: Practical lab: inspect packet path](#slide-48-practical-lab-inspect-packet-path)
- [Slide 49: Cleanup and reset](#slide-49-cleanup-and-reset)
- [Slide 50: Final summary](#slide-50-final-summary)

## Slide 1: Combined deck · 50 slides

> Visual element(s): 1 image/diagram object(s) on this slide.

Single host foundations · bridges · namespaces · Docker bridge · NAT/port publishing

One practical lab: from single Linux host to Docker published port

---

## Slide 2: Course storyline

A single practical lab grows into a container networking mental model

Step 0
Single host

Step 1
Linux bridge

Step 2
namespace + veth

Step 3
Docker bridge

Step 4
NAT + publish

Step 5
end-to-end

One continuous demo: Linux host → br0 → namespaces → Docker bridge → published nginx port

---

## Slide 3: Lab/demo topology

Everything runs on a single Linux VM or bare-metal host

Linux host
Ubuntu/Debian/Rocky

```bash
br0 / Docker bridge
software switching
```

namespaces / containers
virtual hosts

```bash
iptables/NAT
packet translation
```

Prerequisites

$ sudo apt install docker.io iproute2 iputils-ping tcpdump conntrack nginx curl

$ sudo usermod -aG docker $USER

# log out and back in after adding docker group

---

## Slide 4: Step 0

Single Host Configuration

---

## Slide 5: Practical TCP/IP stack

Every later container packet still follows this model

Application
HTTP, SSH, DNS

Transport
TCP / UDP ports

Internet
IPv4 + routing

Link
Ethernet + ARP

Physical
NIC / cable / Wi-Fi

Troubleshooting rule: prove each layer before moving down

---

## Slide 6: Layer-to-command mapping

Use the right tool for the layer you are testing

Layer

What you check

Linux commands

Application

Service, URL, DNS name

curl, dig, getent, logs

Transport

TCP/UDP ports and sessions

ss, nc, tcpdump

Internet

IP address and route

ip addr, ip route, ping

Link

MAC, ARP/neighbor, state

ip link, ip neigh, ethtool

Physical

Carrier, driver, medium

ethtool, dmesg, cable

---

## Slide 7: IPv4 ranges: public vs private

Private addresses need routing/NAT to reach the Internet in most labs

Range

Prefix

Typical use

10.0.0.0 – 10.255.255.255

10.0.0.0/8

Enterprise/internal networks

172.16.0.0 – 172.31.255.255

172.16.0.0/12

Internal/container networks

192.168.0.0 – 192.168.255.255

192.168.0.0/16

Home/small office/LAN labs

Public IPv4

Internet-routable space

External services

Modern routing uses CIDR/prefix length, not old classful thinking

---

## Slide 8: Read host addressing

Start by observing before changing configuration

Terminal

$ ip -br link

lo        UNKNOWN   00:00:00:00:00:00

ens160    UP        00:50:56:aa:bb:cc

$ ip -br addr

ens160    UP        192.168.10.25/24 fe80::250:56ff:feaa:bbcc/64

Key: address + prefix + interface state

---

## Slide 9: Routing: what path will the kernel choose?

ip route get is the fastest routing sanity check

Terminal

$ ip route

default via 192.168.10.1 dev ens160

192.168.10.0/24 dev ens160 proto kernel scope link src 192.168.10.25

$ ip route get 8.8.8.8

8.8.8.8 via 192.168.10.1 dev ens160 src 192.168.10.25

Linux uses longest prefix match, just like routers

---

## Slide 10: DNS and sockets are separate problems

Do not confuse routing, DNS and application binding

Terminal

$ getent hosts example.com

93.184.216.34 example.com

$ ss -ltnp

LISTEN 0.0.0.0:22       sshd

LISTEN 127.0.0.1:8080   python

If ping 8.8.8.8 works but names fail: suspect DNS

---

## Slide 11: Step 0 demo checkpoint

Single-host baseline before virtual networking

Demo commands

$ ip -br link

$ ip -br addr

Expected outcome
You can identify interface, IP, route, DNS, listeners and packets

$ ip route get 8.8.8.8

$ ip neigh

$ getent hosts example.com

$ ss -ltnp

$ tcpdump -ni any icmp

---

## Slide 12: Step 1

Linux bridge as a software switch

---

## Slide 13: Linux bridge mental model

A Linux bridge acts like a software Layer 2 switch

```bash
Linux bridge
br0
```

Namespace / VM / Container

```bash
veth / tap
bridge port
```

Physical NIC
optional uplink

Cisco analogy: bridge FDB ≈ CAM table

---

## Slide 14: Create br0

First lab step: create a Linux bridge

Terminal

$ sudo ip link add br0 type bridge

$ sudo ip link set br0 up

$ ip -br link show br0

br0       UP       8e:5a:0d:40:11:01

br0 is now a software switch with no ports attached yet

---

## Slide 15: Inspect bridge ports and FDB

Linux bridge forwarding is MAC-based

Terminal

$ bridge link

# shows interfaces enslaved to a bridge

$ bridge fdb show br br0

52:54:00:aa:10:11 dev veth1 master br0

52:54:00:aa:10:12 dev veth2 master br0

FDB answers: which MAC lives behind which bridge port?

---

## Slide 16: Cisco CAM vs Linux FDB

Same switching logic, different command surface

Cisco switch

Linux bridge

Purpose

show mac address-table

bridge fdb show

learned MAC addresses

interface Gi1/0/1

dev veth1

port where MAC is learned

VLAN-aware switch

bridge vlan

VLAN filtering/port membership

CAM table troubleshooting

FDB troubleshooting

find where frames go

---

## Slide 17: Step 1 demo checkpoint

You have created and inspected a virtual switch

Demo commands

$ ip link add br0 type bridge

$ ip link set br0 up

Expected outcome
You can explain br0 as a software switch and FDB as a CAM-like table

$ ip link show type bridge

$ bridge link

$ bridge fdb show br br0

---

## Slide 18: Step 2

Network namespace + veth + bridge

---

## Slide 19: Network namespace mental model

A namespace is an isolated network stack

```bash
Default host namespace
ens160, routes, sockets
```

ns1
eth0, routes, sockets

ns2
eth0, routes, sockets

Cisco-friendly analogy: a namespace is like a lightweight isolated host/VRF context

---

## Slide 20: veth pair mental model

A veth pair is a virtual Ethernet cable

ns1
eth0

```bash
host side
veth-ns1
```

```bash
veth pair
virtual cable
```

Anything entering one side exits the other side

---

## Slide 21: Namespace + veth + bridge topology

This is the manual version of a basic container network

br-demo
software switch

```bash
ns1
192.168.50.11
```

```bash
ns2
192.168.50.12
```

veth1-br

veth2-br

---

## Slide 22: Build the namespace lab

Create namespaces, bridge and veth pairs

Terminal

$ sudo ip netns add ns1

$ sudo ip netns add ns2

$ sudo ip link add br-demo type bridge

$ sudo ip link set br-demo up

$ sudo ip link add veth1-br type veth peer name eth0 netns ns1

$ sudo ip link add veth2-br type veth peer name eth0 netns ns2

---

## Slide 23: Attach and address

Host-side veth interfaces become bridge ports

Terminal

$ sudo ip link set veth1-br master br-demo

$ sudo ip link set veth2-br master br-demo

$ sudo ip link set veth1-br up

$ sudo ip link set veth2-br up

$ sudo ip -n ns1 addr add 192.168.50.11/24 dev eth0

$ sudo ip -n ns2 addr add 192.168.50.12/24 dev eth0

$ sudo ip -n ns1 link set eth0 up

$ sudo ip -n ns2 link set eth0 up

---

## Slide 24: Test and inspect

Ping across the bridge and inspect the FDB

Terminal

$ sudo ip netns exec ns1 ping -c 2 192.168.50.12

64 bytes from 192.168.50.12: icmp_seq=1 ttl=64 time=0.09 ms

$ bridge fdb show br br-demo

52:54:00:aa:10:11 dev veth1-br master br-demo

52:54:00:aa:10:12 dev veth2-br master br-demo

$ sudo tcpdump -ni br-demo icmp

---

## Slide 25: Step 2 checkpoint

The packet path is now visible

ns1

veth1

bridge
FDB

veth2

ns2

reply

Manual container-like network: isolated stacks + virtual cables + software switch

---

## Slide 26: Step 3

Docker bridge networking

---

## Slide 27: Docker maps to the primitives

Docker automates the topology you built manually

Manual lab

Docker equivalent

ip netns add ns1

container network namespace

ip link add ... type veth

Docker creates veth pair

ip link set veth master br0

Docker attaches host veth to bridge

ip addr add ...

Docker IPAM assigns container IP

bridge fdb show

bridge learns container MACs

---

## Slide 28: Inspect Docker default bridge

Start by looking at Docker network state

Terminal

$ docker network ls

NETWORK ID     NAME      DRIVER    SCOPE

6b7c5e7f9a01   bridge    bridge    local

b58d781f1234   host      host      local

0f2d9ef77821   none      null      local

$ docker network inspect bridge

---

## Slide 29: Default bridge topology

Containers on the same default bridge can communicate by IP

```bash
docker0
172.17.0.1/16
```

```bash
c1
172.17.0.2
```

```bash
c2
172.17.0.3
```

veth

---

## Slide 30: Run two containers on default bridge

Default bridge works by IP; name resolution is limited

Terminal

$ docker run -dit --name c1 alpine sh

$ docker run -dit --name c2 alpine sh

$ docker inspect -f "{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}" c2

172.17.0.3

$ docker exec c1 ping -c 2 172.17.0.3   # works

$ docker exec c1 ping -c 1 c2           # usually fails on default bridge

---

## Slide 31: Create a user-defined bridge

Preferred pattern for multi-container apps

Terminal

$ docker network create app-net

$ docker run -dit --name web --network app-net nginx:alpine

$ docker run -dit --name client --network app-net alpine sh

$ docker network inspect app-net

User-defined bridge gives per-app isolation and built-in container-name DNS

---

## Slide 32: DNS resolution between containers

Container names become practical service-discovery names

Terminal

$ docker exec client cat /etc/resolv.conf

nameserver 127.0.0.11

$ docker exec client getent hosts web

172.18.0.2      web

$ docker exec client wget -qO- http://web | head

<!DOCTYPE html>

---

## Slide 33: Step 3 checkpoint

Docker bridge is now understandable

client

veth

```bash
app-net
bridge + DNS
```

web

HTTP reply

The same namespace + veth + bridge model is now automated by Docker

---

## Slide 34: Step 4

Docker NAT / port publishing

---

## Slide 35: Why Docker needs NAT

Containers use private addressing; external networks usually do not route back

host NAT
src = host IP

```bash
container
172.18.0.3
```

```bash
Docker bridge
172.18.0.1
```

Internet
8.8.8.8

Outbound: POSTROUTING MASQUERADE changes source from container IP to host IP

---

## Slide 36: Outbound NAT path

Container reaching the Internet

container

veth

bridge

FORWARD

POSTROUTING
MASQUERADE

NIC

The outside world usually sees the host IP, not the container IP

---

## Slide 37: Inspect NAT and conntrack

NAT is both rules and state

Terminal

$ sudo iptables-save | sed -n "/\*nat/,/COMMIT/p"

-A POSTROUTING -s 172.18.0.0/16 ! -o br-xxxx -j MASQUERADE

$ sudo conntrack -L | grep 172.18.0.3

tcp 6 src=172.18.0.3 dst=93.184.216.34 sport=51234 dport=443 ...

conntrack remembers translations so return traffic reaches the correct container

---

## Slide 38: Publish a container port

External client reaches host port; Docker DNAT forwards to container

Terminal

$ docker run -d --name web --network app-net -p 8080:80 nginx:alpine

$ docker ps --format "table {{.Names}}\t{{.Ports}}"

NAMES   PORTS

web     0.0.0.0:8080->80/tcp

$ curl -I http://127.0.0.1:8080

HTTP/1.1 200 OK

---

## Slide 39: Inbound published-port path

DNAT changes destination from host:8080 to container:80

client

host NIC

PREROUTING
DNAT

FORWARD

bridge

container

Important: published container traffic typically uses FORWARD, not only INPUT

---

## Slide 40: Inspect DNAT rules

Docker-managed chains contain the translation

Terminal

$ sudo iptables-save | grep -E "8080|DNAT|DOCKER"

-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER

-A DOCKER ! -i br-xxxx -p tcp --dport 8080 \

-j DNAT --to-destination 172.18.0.2:80

Destination changes from host:8080 to container:80 before forwarding

---

## Slide 41: INPUT vs FORWARD

The most common firewall confusion

Traffic

Destination after routing/NAT

Important chain/path

SSH to host

Linux host itself

INPUT

host:8080 → container:80

container behind bridge

PREROUTING DNAT + FORWARD

container → Internet

external destination

FORWARD + POSTROUTING NAT

host process → Internet

OUTPUT + POSTROUTING

Correct rule in the wrong chain is still wrong

---

## Slide 42: Packet capture proves NAT

Capture before and after the translation point

Terminal

# before outbound NAT: on bridge

$ sudo tcpdump -ni br-xxxx host 8.8.8.8

IP 172.18.0.3 > 8.8.8.8: ICMP echo request

# after outbound NAT: on physical NIC

$ sudo tcpdump -ni ens160 host 8.8.8.8

IP 10.0.0.20 > 8.8.8.8: ICMP echo request

---

## Slide 43: Step 4 checkpoint

You can now explain Docker egress and published ports

Outbound
container → Internet

SNAT/MASQ
POSTROUTING

Inbound
host:8080 → container:80

DNAT
PREROUTING + FORWARD

Docker NAT = DNAT + MASQUERADE + FORWARD + conntrack

---

## Slide 44: Step 5

End-to-end mental model and practical lab

---

## Slide 45: The main mental model

This is the diagram you should be able to draw from memory

Container namespace

veth pair

Every troubleshooting question becomes:
Where is the packet now, and where should it go next?

Each layer is both a forwarding point and an inspection point.

Linux bridge

```bash
host routing +
iptables/NAT
```

physical NIC

network

---

## Slide 46: End-to-end troubleshooting decision tree

Classify the failure before changing the configuration

1
App works locally?

```bash
2
Container IP/route?
```

3
Bridge/FDB?

4
DNS/name?

5
NAT/FORWARD?

No at step 1: application issue
No at step 2: namespace/container network issue
No at step 3: bridge/veth issue
No at step 4: Docker DNS/network attachment issue
No at step 5: firewall/NAT/routing issue

---

## Slide 47: Practical lab: build and verify

One compact demo that touches all course concepts

Lab script · Part 1

# 1) host baseline

ip -br addr && ip route get 8.8.8.8

# 2) create app network and containers

docker network create app-net

docker run -d --name web --network app-net -p 8080:80 nginx:alpine

docker run -dit --name client --network app-net alpine sh

# 3) verify service discovery and HTTP

docker exec client getent hosts web

docker exec client wget -qO- http://web | head

---

## Slide 48: Practical lab: inspect packet path

Show Docker from Linux host perspective

Lab script · Part 2

# Docker view

docker network inspect app-net

docker ps

# Linux bridge view

ip link show type bridge

bridge link

bridge fdb show

# NAT/firewall view

iptables-save | grep -E "8080|DNAT|MASQUERADE|DOCKER"

conntrack -L | grep 172.18

# packet evidence

tcpdump -ni any tcp port 8080

---

## Slide 49: Cleanup and reset

Keep labs reproducible

Cleanup commands

$ docker rm -f web client c1 c2

$ docker network rm app-net

$ sudo ip netns del ns1 2>/dev/null || true

$ sudo ip netns del ns2 2>/dev/null || true

$ sudo ip link del br-demo 2>/dev/null || true

$ sudo ip link del br0 2>/dev/null || true

$ docker network ls

$ ip -br link

Clean state = easier troubleshooting and repeatable demos

---

## Slide 50: Final summary

The whole course in one sentence

Container namespace

```bash
Containers are not magic.
They are Linux networking primitives automated by Docker.
```

veth pair

Linux bridge

```bash
Single host TCP/IP gives you the baseline.
Bridge gives you software switching.
Namespace gives you isolation.
veth gives you the cable.
Docker gives you automation.
iptables/NAT gives you outside connectivity.
```

```bash
host routing +
iptables/NAT
```

physical NIC

network

Follow the packet — the model tells you where to look.

---
