# Iptables and Basics of the Linux Kernel Firewall — Lab Guide

This lab guide follows the **Iptables and Basics of the Linux Kernel Firewall** lab sequence.

The goal is to practice how Docker uses the Linux firewall path:

```text
published host port
  → DNAT
  → FORWARD
  → Docker bridge
  → container service
```

We will also inspect outbound NAT, connection tracking, and the `DOCKER-USER` chain.

> The commands are based on the original `Iptables_LAB.txt`.  
> Some outputs may differ slightly depending on your Docker version, Linux distribution, and iptables/nftables backend.

---

## 0. Lab prerequisites

Before starting this lab, make sure Docker works and the basic tools are installed:

```bash
docker ps
iptables --version
sudo iptables-save | head
tcpdump --version
conntrack -V
```

If `conntrack` is missing, install it:

```bash
sudo apt install conntrack
```

This lab assumes that we use a user-defined Docker bridge network called `app-net`.

---

## 1. Create the Docker network and published web container

First, create a Docker bridge network and run an nginx container with a published port.

```bash
docker network create app-net
docker run -d --name web --network app-net -p 8080:80 nginx:alpine
```

Verify the container, published port, and network:

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}\t{{.Networks}}'
```

Expected idea:

```text
NAMES   PORTS                  NETWORKS
web     0.0.0.0:8080->80/tcp   app-net
```

What this means:

```text
host TCP/8080 → container TCP/80
```

Docker publishes port `8080` on the Linux host and forwards it to port `80` inside the `web` container.

---

## 2. Verify the application and container IP

Test the published service from the Linux host:

```bash
curl -I http://127.0.0.1:8080
```

Expected result:

```text
HTTP/1.1 200 OK
```

Now inspect the container IP address:

```bash
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' web
```

Example output:

```text
172.18.0.2
```

Check that nginx is listening inside the container:

```bash
docker exec web netstat -ltnp
```

Expected idea:

```text
LISTEN 0.0.0.0:80
```

> Note: the `nginx:alpine` image is minimal. It may not include `ss`, so this lab uses `netstat`.  
> If `netstat` is also missing, you can still verify the service with `curl` from the host, or install tools temporarily inside the container.

Optional troubleshooting tools inside Alpine:

```bash
docker exec web apk add --no-cache iproute2
docker exec web ss -ltnp
```

---

## 3. Inspect Docker-generated NAT rules

Now inspect the firewall/NAT rules that Docker created automatically:

```bash
sudo iptables-save | grep -E '8080|DNAT|MASQUERADE|DOCKER'
```

You should see output similar to:

```bash
-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
-A DOCKER ! -i br-xxxx -p tcp -m tcp --dport 8080 \
    -j DNAT --to-destination 172.18.0.2:80
-A POSTROUTING -s 172.18.0.0/16 ! -o br-xxxx -j MASQUERADE
```

Important points:

- `DNAT` is used for the published port.
- `host:8080` is translated to `container:80`.
- `MASQUERADE` is used for outbound container traffic.
- Docker manages these rules automatically.

---

## 4. Prove the packet path with tcpdump

We will capture the same flow at different points.

### Terminal 1 — capture host port

```bash
sudo tcpdump -ni any tcp port 8080
```

This shows traffic as it reaches the host published port.

### Terminal 2 — capture container port on Docker bridge

First identify the Docker bridge interface:

```bash
ip link show type bridge
```

or:

```bash
docker network inspect app-net | grep -i bridge
```

Then replace `br-xxxx` with the actual bridge name:

```bash
sudo tcpdump -ni br-xxxx tcp port 80
```

### Terminal 3 — generate traffic

```bash
curl http://127.0.0.1:8080
```

What to observe:

```text
Before DNAT: traffic is seen as host port 8080.
After DNAT: traffic is seen as container port 80.
```

This demonstrates that Docker port publishing is not only a Docker CLI feature; it is implemented through Linux packet forwarding and NAT.

Stop `tcpdump` with `Ctrl+C`.

---

## 5. Inspect conntrack state

Connection tracking remembers the state of flows and NAT translations.

Run:

```bash
sudo conntrack -L -p tcp | grep 172.18.0.2
```

Example output:

```text
tcp 6 431999 ESTABLISHED src=127.0.0.1 dst=127.0.0.1 sport=51522 dport=8080
    src=172.18.0.2 dst=172.18.0.1 sport=80 dport=51522
```

The exact output depends on:

- whether traffic comes from localhost or another host,
- the Docker bridge subnet,
- your Docker version,
- your iptables/nftables backend.

The important idea:

```text
iptables rules define translation behavior.
conntrack remembers active translated flows.
```

---

## 6. Add a simple DOCKER-USER policy

Docker provides the `DOCKER-USER` chain for administrator-defined filtering policy.

This is safer than editing Docker-managed chains directly.

Example policy:

```bash
sudo iptables -I DOCKER-USER 1 -s 10.0.0.50 -p tcp --dport 80 -j ACCEPT
sudo iptables -A DOCKER-USER -p tcp --dport 80 -j DROP
```

This example means:

```text
Allow source 10.0.0.50 to reach forwarded TCP/80 traffic.
Drop other forwarded TCP/80 traffic.
```

Inspect the rules and counters:

```bash
sudo iptables -L DOCKER-USER -n -v --line-numbers
```

Why counters matter:

```text
If packet counters increase, the rule is being hit.
If counters stay at zero, traffic may be using another path or another chain.
```

> In many local-only tests with `curl http://127.0.0.1:8080`, behavior can differ from external-client traffic.  
> For a clearer `DOCKER-USER` demo, test from another host or from a source that really enters the forwarding path.

---

## 7. Remove lab firewall rules safely

Before removing rules, list them with line numbers:

```bash
sudo iptables -L DOCKER-USER -n -v --line-numbers
```

Delete by line number, starting with the highest number first:

```bash
sudo iptables -D DOCKER-USER 2
sudo iptables -D DOCKER-USER 1
```

Why delete highest number first?

```text
When you delete rule 1, all following rules shift up.
Deleting from the bottom avoids deleting the wrong rule.
```

Only in a disposable lab environment, you may flush the whole `DOCKER-USER` chain:

```bash
sudo iptables -F DOCKER-USER
```

Warning:

```text
Never casually flush production firewall rules.
```

---

## 8. Lab cleanup

At the end of the lab, remove the demo container and Docker network:

```bash
docker rm -f web
docker network rm app-net
```

If you added any temporary `DOCKER-USER` rules, remove only those lab rules:

```bash
sudo iptables -L DOCKER-USER -n -v --line-numbers
sudo iptables -D DOCKER-USER <line-number>
```

Verify cleanup:

```bash
docker ps -a
docker network ls
```

A clean state makes troubleshooting easier and keeps demos repeatable.

---

## 9. Troubleshooting notes

### Container name conflict

If Docker reports that the container name is already in use:

```text
Conflict. The container name "/web" is already in use.
```

Remove the existing container:

```bash
docker rm -f web
```

Then run the container again.

---

### Port 8080 already in use

If Docker reports that port `8080` is already allocated, check what uses it:

```bash
sudo ss -ltnp | grep 8080
```

Use another host port if needed:

```bash
docker run -d --name web --network app-net -p 8081:80 nginx:alpine
curl -I http://127.0.0.1:8081
```

---

### `ss` is missing inside the container

The `nginx:alpine` image is minimal and may not include `ss`.

Use:

```bash
docker exec web netstat -ltnp
```

Or install `ss` temporarily:

```bash
docker exec web apk add --no-cache iproute2
docker exec web ss -ltnp
```

---

### Wrong bridge name

If `br-xxxx` does not exist, find the real bridge name:

```bash
ip link show type bridge
docker network inspect app-net | grep -i bridge
```

Then use the real bridge name in `tcpdump`.

---

## 10. Final mental model

For Docker published ports, remember:

```text
client
  → host:8080
  → PREROUTING / DOCKER chain
  → DNAT to container:80
  → FORWARD
  → Docker bridge
  → web container
```

For outbound container traffic, remember:

```text
container
  → Docker bridge
  → FORWARD
  → POSTROUTING MASQUERADE
  → physical NIC
  → network
```

Main troubleshooting rule:

```text
Follow the packet.
Check the correct chain.
Use counters, conntrack, and tcpdump to prove the path.
```
