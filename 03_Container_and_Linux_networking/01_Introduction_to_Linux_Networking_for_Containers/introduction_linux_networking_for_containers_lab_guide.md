# Introduction to Linux Networking for Containers — Lab Guide

This lab guide follows the **Introduction to Linux Networking for Containers** deck and gives students a practical, step-by-step workflow they can run during the session.

The goal is not only to copy commands, but to understand how the packet path grows:

```text
Linux host
  → Linux bridge
  → network namespaces
  → veth pairs
  → Docker bridge
  → NAT / port publishing
  → packet inspection
```

> The commands are written for a Linux lab VM or bare-metal Linux host with Docker installed. Some commands require `sudo`.

---

## 0. Lab prerequisites

Install the basic tools used in the lab:

```bash
sudo apt install docker.io iproute2 iputils-ping tcpdump conntrack nginx curl
```

Allow your user to run Docker commands without `sudo`:

```bash
sudo usermod -aG docker $USER
```

Log out and log back in after adding your user to the `docker` group.

Verify Docker works:

```bash
docker version
docker ps
```

---

## 1. Step 0 — Single-host baseline

Before creating bridges, namespaces, or containers, inspect the normal Linux host networking state.

### 1.1 Interfaces and addresses

```bash
ip -br link
ip -br addr
```

Check which interfaces exist, which interface is `UP`, and which IPv4 address/prefix the host uses.

### 1.2 Routing sanity check

```bash
ip route get 8.8.8.8
```

This answers a useful question: if the Linux kernel sends a packet to `8.8.8.8`, which interface, gateway, and source IP will it use?

### 1.3 Neighbor table

```bash
ip neigh
```

This shows ARP/neighbor information. It is useful when routing looks correct, but Layer 2 resolution may be failing.

### 1.4 DNS and sockets

```bash
getent hosts example.com
ss -ltnp
```

Use `getent hosts` to test name resolution. Use `ss -ltnp` to see which TCP services are listening.

### 1.5 Optional packet capture

In one terminal, run:

```bash
sudo tcpdump -ni any icmp
```

In another terminal, generate ICMP traffic:

```bash
ping -c 2 8.8.8.8
```

Stop `tcpdump` with `Ctrl+C`.

---

## 2. Step 1 — Linux bridge as a software switch

A Linux bridge acts like a software Layer 2 switch. It learns MAC addresses and forwards frames between connected interfaces.

### 2.1 Create a Linux bridge

```bash
sudo ip link add br0 type bridge
sudo ip link set br0 up
ip -br link show br0
```

Expected idea:

```text
br0 is now a software switch, but no ports are connected yet.
```

### 2.2 Inspect bridge ports and FDB

```bash
bridge link
bridge fdb show br br0
```

At this point, `br0` may not show much because no interfaces are connected to it yet.

The important concept:

```text
bridge fdb show ≈ show mac address-table
```

The Linux bridge FDB answers: which MAC address is reachable behind which bridge port?

---

## 3. Step 2 — Network namespaces + veth + bridge

Now we manually build a simple container-like network:

```text
ns1 -- veth -- br-demo -- veth -- ns2
```

Each namespace has its own isolated network stack. A veth pair acts like a virtual Ethernet cable. The bridge acts like a software switch.

### 3.1 Create two network namespaces

```bash
sudo ip netns add ns1
sudo ip netns add ns2
ip netns list
```

### 3.2 Create and enable a bridge

```bash
sudo ip link add br-demo type bridge
sudo ip link set br-demo up
ip -br link show br-demo
```

### 3.3 Create veth pairs

Create the first veth pair. One side stays on the host as `veth1-br`; the other side becomes `eth0` inside `ns1`.

```bash
sudo ip link add veth1-br type veth peer name eth0 netns ns1
```

Create the second veth pair. One side stays on the host as `veth2-br`; the other side becomes `eth0` inside `ns2`.

```bash
sudo ip link add veth2-br type veth peer name eth0 netns ns2
```

### 3.4 Attach host-side veth interfaces to the bridge

```bash
sudo ip link set veth1-br master br-demo
sudo ip link set veth2-br master br-demo
sudo ip link set veth1-br up
sudo ip link set veth2-br up
bridge link
```

### 3.5 Configure IP addresses inside namespaces

```bash
sudo ip -n ns1 addr add 192.168.50.11/24 dev eth0
sudo ip -n ns2 addr add 192.168.50.12/24 dev eth0
sudo ip -n ns1 link set eth0 up
sudo ip -n ns2 link set eth0 up
```

Optional: bring loopback up inside each namespace.

```bash
sudo ip -n ns1 link set lo up
sudo ip -n ns2 link set lo up
```

Verify namespace addressing:

```bash
sudo ip -n ns1 -br addr
sudo ip -n ns2 -br addr
```

### 3.6 Test namespace-to-namespace connectivity

Ping from `ns1` to `ns2`:

```bash
sudo ip netns exec ns1 ping -c 2 192.168.50.12
```

Inspect the bridge FDB:

```bash
bridge fdb show br br-demo
```

Capture ICMP on the bridge:

```bash
sudo tcpdump -ni br-demo icmp
```

Generate traffic again in another terminal:

```bash
sudo ip netns exec ns1 ping -c 2 192.168.50.12
```

Stop `tcpdump` with `Ctrl+C`.

---

## 4. Step 3 — Docker bridge networking

Docker automates the primitives we just built manually.

| Manual lab | Docker equivalent |
|---|---|
| `ip netns add` | container network namespace |
| `ip link add ... type veth` | Docker creates a veth pair |
| `ip link set veth master bridge` | Docker attaches host-side veth to bridge |
| manual IP configuration | Docker IPAM assigns the container IP |
| bridge FDB learning | bridge learns container MAC addresses |

### 4.1 Inspect Docker networks

```bash
docker network ls
docker network inspect bridge
```

The default Docker bridge is usually named `bridge` in Docker and often backed by `docker0` on the Linux host.

### 4.2 Run two containers on the default bridge

```bash
docker run -dit --name c1 alpine sh
docker run -dit --name c2 alpine sh
```

Get the IP address of `c2`:

```bash
docker inspect -f "{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}" c2
```

Test connectivity from `c1` to the IP address of `c2`:

```bash
docker exec c1 ping -c 2 172.17.0.3
```

Now try to ping by name:

```bash
docker exec c1 ping -c 1 c2
```

On the default bridge this usually fails, because container-name DNS is limited there.

### 4.3 Create a user-defined bridge network

User-defined bridge networks are preferred for multi-container applications.

```bash
docker network create app-net
docker run -dit --name web --network app-net nginx:alpine
docker run -dit --name client --network app-net alpine sh
docker network inspect app-net
```

### 4.4 Test Docker DNS and HTTP connectivity

Check DNS configuration inside the client container:

```bash
docker exec client cat /etc/resolv.conf
```

Resolve the web container by name:

```bash
docker exec client getent hosts web
```

Test HTTP connectivity from `client` to `web`:

```bash
docker exec client wget -qO- http://web | head
```

Expected result: the client container can resolve `web` and reach the nginx service.

If `wget` is missing, install it inside the client container:

```bash
docker exec client apk add --no-cache wget
```

---

## 5. Step 4 — Docker NAT and port publishing

So far, containers communicate inside Docker bridge networks. Now we look at traffic crossing the Linux host boundary:

- container to Internet,
- host or external client to a container service.

Docker commonly uses:

- `MASQUERADE` for outbound container traffic,
- `DNAT` for published ports,
- `FORWARD` for traffic routed through the host,
- `conntrack` to remember NAT state.

### 5.1 Inspect NAT rules

```bash
sudo iptables-save | sed -n "/\*nat/,/COMMIT/p"
```

Look for rules containing `MASQUERADE`, `DOCKER`, or `DNAT`.

Example:

```text
-A POSTROUTING -s 172.18.0.0/16 ! -o br-xxxx -j MASQUERADE
```

This means Docker can translate outbound container traffic so that it appears to come from the Linux host.

### 5.2 Inspect connection tracking

```bash
sudo conntrack -L | grep 172.18
```

If there is no output, first generate some traffic from a container:

```bash
docker exec client wget -qO- http://web | head
```

or test external connectivity if available:

```bash
docker exec client ping -c 2 8.8.8.8
```

Then run:

```bash
sudo conntrack -L | grep 172.18
```

The idea:

```text
NAT is both rules and state.
iptables-save shows the rules.
conntrack shows active tracked flows.
```

### 5.3 Publish a container port

Earlier we started `web` without a published host port. Docker cannot normally add `-p` port mappings to an already-created container.

For a clean lab, remove and recreate `web` with port publishing:

```bash
docker rm -f web
docker run -d --name web --network app-net -p 8080:80 nginx:alpine
```

Verify published ports:

```bash
docker ps --format "table {{.Names}}\t{{.Ports}}"
```

Expected output should include:

```text
web     0.0.0.0:8080->80/tcp
```

Test from the Linux host:

```bash
curl -I http://127.0.0.1:8080
```

Expected result:

```text
HTTP/1.1 200 OK
```

Conceptually:

```text
host:8080  →  container:80
```

### 5.4 Inspect Docker DNAT rules

```bash
sudo iptables-save | grep -E "8080|DNAT|DOCKER"
```

Look for a rule similar to:

```text
-A DOCKER ! -i br-xxxx -p tcp --dport 8080 \
    -j DNAT --to-destination 172.18.0.2:80
```

Important concept:

```text
Published container traffic usually uses PREROUTING DNAT + FORWARD.
It is not simply INPUT traffic to the Linux host.
```

### 5.5 Packet capture before and after NAT

Identify the Docker bridge interface name:

```bash
ip link show type bridge
```

or:

```bash
docker network inspect app-net | grep -i bridge
```

You may see something like `br-123456789abc`. Replace `br-xxxx` below with the actual bridge interface name.

Capture on the Docker bridge:

```bash
sudo tcpdump -ni br-xxxx host 8.8.8.8
```

Capture on the physical NIC:

```bash
sudo tcpdump -ni ens160 host 8.8.8.8
```

In another terminal, generate traffic from the client container:

```bash
docker exec client ping -c 2 8.8.8.8
```

What to observe:

- on the Docker bridge, the source is the container IP,
- on the physical NIC, the source is usually the Linux host IP.

This proves outbound NAT/MASQUERADE.

If your physical interface is not `ens160`, find it with:

```bash
ip route get 8.8.8.8
```

Use the interface shown in the output.

---

## 6. Step 5 — End-to-end practical lab

This compact demo touches the main concepts from the course.

### 6.1 Build and verify

```bash
# 1) host baseline
ip -br addr && ip route get 8.8.8.8

# 2) create app network and containers
docker network create app-net
docker rm -f web client 2>/dev/null || true
docker run -d --name web --network app-net -p 8080:80 nginx:alpine
docker run -dit --name client --network app-net alpine sh

# 3) verify service discovery and HTTP
docker exec client getent hosts web
docker exec client wget -qO- http://web | head
```

Expected result:

```text
The client container can resolve web and retrieve content from nginx.
```

### 6.2 Inspect packet path from the host

```bash
# Docker view
docker network inspect app-net
docker ps

# Linux bridge view
ip link show type bridge
bridge link
bridge fdb show

# NAT/firewall view
sudo iptables-save | grep -E "8080|DNAT|MASQUERADE|DOCKER"
sudo conntrack -L | grep 172.18

# packet evidence
sudo tcpdump -ni any tcp port 8080
```

In another terminal, generate traffic:

```bash
curl -I http://127.0.0.1:8080
```

Stop `tcpdump` with `Ctrl+C`.

The purpose is to connect all views:

```text
Docker view → Linux bridge view → NAT/firewall view → packet capture
```

---

## 7. Troubleshooting hints

### Container name conflict

If Docker says the name is already in use, remove the existing container and recreate it:

```bash
docker rm -f web
```

### Port already allocated

If Docker says port `8080` is already allocated, check what uses it:

```bash
sudo ss -ltnp | grep 8080
```

You can either stop the conflicting service or use another host port:

```bash
docker run -d --name web --network app-net -p 8081:80 nginx:alpine
curl -I http://127.0.0.1:8081
```

### `ss` missing inside Alpine container

Minimal images may not include troubleshooting tools.

If this fails:

```bash
docker exec web ss -ltnp
```

Use BusyBox `netstat` if available:

```bash
docker exec web netstat -ltn
```

Or install `iproute2` inside the running Alpine container:

```bash
docker exec web apk add --no-cache iproute2
docker exec web ss -ltnp
```

### Wrong bridge name

If `br-xxxx` does not exist, list bridge interfaces:

```bash
ip link show type bridge
```

Then use the real bridge name in `tcpdump`.

### DNS works differently on default bridge

On Docker's default bridge, container-name resolution is limited. For name-based communication, use a user-defined bridge:

```bash
docker network create app-net
```

---

## 8. Cleanup and reset

At the end of the lab, remove demo containers, Docker networks, namespaces, and manual bridges.

```bash
docker rm -f web client c1 c2
docker network rm app-net
sudo ip netns del ns1 2>/dev/null || true
sudo ip netns del ns2 2>/dev/null || true
sudo ip link del br-demo 2>/dev/null || true
sudo ip link del br0 2>/dev/null || true
docker network ls
ip -br link
```

A clean state makes troubleshooting easier and keeps demos repeatable.

---

## 9. Final mental model

Remember the full packet path:

```text
container namespace
  → veth pair
  → Linux bridge
  → host routing + iptables/NAT
  → physical NIC
  → network
```

When something fails, ask:

```text
Where is the packet now?
Where should it go next?
Which Linux object should I inspect at that point?
```
