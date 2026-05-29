# Chapter 7: Docker Networking Threat Vectors

## Theory

Once the mechanics are understood, the threat model returns to attacker workflows. Docker networking threat vectors usually involve exposure mistakes, lateral movement, egress, metadata access, host gateway access, DNS abuse, tunnel abuse, unsafe capabilities, and weak observability. These issues are common because Docker makes networking easy and because default connectivity is often more permissive than teams realize.

The most important defensive mindset is to treat every connection as a policy decision. A web container should not automatically be able to reach a database. A database should not be published to the host unless there is a specific administrative need and a strong control around it. A container should not have internet egress merely because it was easier to leave it open. A debug container with `NET_ADMIN` should not be treated like an ordinary shell.

**Mechanism:** Docker makes connectivity easy by default: bridge networks provide routes, Compose provides service discovery, `ports` publishes services on the host, capabilities can extend what a container can do to the network stack, and the Docker API can create or modify containers with powerful host access.

**Security consequence:** common threat vectors are usually not exotic. They are ordinary Docker features used without clear ownership: broad port publishing, flat networks, reachable host gateways, unrestricted egress, metadata access, exposed APIs, DNS leakage, and elevated network capabilities.

## 7.1 Accidental Public Exposure

### Red-Team Practical

Create an intentionally risky Compose file.

```bash
cat > compose-exposed.yml <<'YAML'
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: insecure
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  adminer:
    image: adminer
    ports:
      - "8081:8080"
YAML
```

Start it and inspect host exposure.

```bash
docker compose -f compose-exposed.yml up -d
docker compose -f compose-exposed.yml ps
ss -tulpen | egrep '5432|6379|8081' || true
```

From another lab host, test exposure.

```bash
nc -vz <docker-host-ip> 5432
nc -vz <docker-host-ip> 6379
curl -I http://<docker-host-ip>:8081
```

Observation: host listeners appear for the database, cache, and admin panel ports, and a second lab host may be able to connect to them.

Attacker perspective: databases, caches, and admin panels are frequently exposed through simple Compose mistakes.

### Blue-Team Practical

Fix the Compose file by removing unnecessary host ports and binding admin tools to localhost.

```bash
cat > compose-exposed-fixed.yml <<'YAML'
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: insecure
    networks:
      - backend
    expose:
      - "5432"

  redis:
    image: redis:7-alpine
    networks:
      - backend
    expose:
      - "6379"

  adminer:
    image: adminer
    ports:
      - "127.0.0.1:8081:8080"
    networks:
      - backend

networks:
  backend:
    internal: true
YAML
```

Apply and check exposure.

```bash
docker compose -f compose-exposed.yml down
docker compose -f compose-exposed-fixed.yml up -d
ss -tulpen | egrep '5432|6379|8081' || true
```

Observation: after the fix, database and Redis no longer appear as host-published services, and Adminer is bound only to localhost.

Defensive interpretation: `ports` should be rare and intentional.

Cleanup.

```bash
docker compose -f compose-exposed-fixed.yml down
```

## 7.2 Host Gateway Access

### Red-Team Practical

Start a container.

```bash
docker run -it --rm nicolaka/netshoot sh
```

Inside.

```sh
GW=$(ip route | awk '/default/ {print $3}')
echo "$GW"

nc -vz "$GW" 22 || true
nc -vz "$GW" 2375 || true
curl -I --max-time 3 "http://$GW:8080" || true
exit
```

Observation: some probes may fail, but the gateway address should be discoverable and any service bound to the bridge address or all interfaces may be reachable.

Attacker perspective: host-local services may be reachable from containers through the bridge gateway.

### Blue-Team Practical

List services listening on the host.

```bash
ss -tulpen
```

Review whether any service is bound to all interfaces or to the Docker bridge address.

```bash
ip addr show docker0
ss -tulpen | grep LISTEN
```

Observation: host listener review identifies whether services are bound to all interfaces, loopback only, or the Docker bridge address.

Defensive interpretation: defenders should explicitly decide whether containers are allowed to reach host services.

## 7.3 Cloud Metadata Access

### Red-Team Practical

From a container, attempt metadata access in a lab-safe way.

```bash
docker run --rm curlimages/curl \
  -m 3 http://169.254.169.254/ || true
```

On a real cloud VM, never run metadata experiments casually because the metadata service may expose sensitive credentials or identity information.

### Blue-Team Practical

Block metadata access through `DOCKER-USER`.

```bash
sudo iptables -I DOCKER-USER -d 169.254.169.254/32 -j DROP
docker run --rm curlimages/curl -m 3 http://169.254.169.254/ || true
sudo iptables -L DOCKER-USER -n -v
sudo iptables -D DOCKER-USER -d 169.254.169.254/32 -j DROP
```

Defensive interpretation: cloud metadata should be treated as a sensitive network destination.

## 7.4 Docker API Exposure

### Red-Team Practical

Check whether a Docker API is exposed on a lab host.

```bash
nc -vz <docker-host-ip> 2375 || true
curl --max-time 3 http://<docker-host-ip>:2375/version || true
```

Observation: secure hosts do not expose an unauthenticated Docker API on `2375`. If it responds, treat it as a critical finding in a lab.

Attacker perspective: an unauthenticated Docker API can be equivalent to host compromise because it may allow an attacker to start privileged containers, mount host paths, and control Docker.

### Blue-Team Practical

Check Docker daemon configuration and listening ports.

```bash
ps aux | grep dockerd | grep -v grep || true
sudo systemctl cat docker 2>/dev/null || true
sudo grep -R "tcp://" /etc/docker /lib/systemd /etc/systemd 2>/dev/null || true
ss -tulpen | grep 2375 || true
ss -tulpen | grep 2376 || true
```

Observation: no unauthenticated listener is present on `2375`. If remote Docker API access exists, it should be deliberately configured, encrypted, authenticated, and restricted.

Defensive interpretation: the Docker API should not be exposed unauthenticated. If remote access is required, it must be authenticated, encrypted, restricted, logged, and justified.

## 7.5 DNS Exfiltration

### Red-Team Practical

Demonstrate the pattern without exfiltrating real data.

```bash
docker run --rm nicolaka/netshoot \
  sh -c 'dig test123.example.com || true'
```

Explain that an attacker can encode chunks of data into subdomains if DNS egress is open. Do not demonstrate real exfiltration.

### Blue-Team Practical

Observe DNS traffic.

```bash
sudo tcpdump -i docker0 -nn port 53
```

In another terminal.

```bash
docker run --rm nicolaka/netshoot \
  sh -c 'dig example.com; dig test123.example.com || true'
```

Observation: tcpdump shows DNS queries from container traffic. In a mature environment, those queries should be centrally logged and attributable.

Defensive interpretation: DNS logging and egress control matter.

## 7.6 NET_ADMIN and NET_RAW

### Red-Team Practical

Show that a normal container has limited network control.

```bash
docker run --rm alpine sh -c 'ip link add dummy0 type dummy 2>/dev/null || echo "failed as expected"'
```

Show that `NET_ADMIN` changes the situation.

```bash
docker run --rm --cap-add NET_ADMIN alpine sh -c 'ip link add dummy0 type dummy && ip link show dummy0'
```

Observation: creating a dummy interface fails in the normal container and succeeds when `NET_ADMIN` is added.

Attacker perspective: capabilities can turn a container into a stronger network actor.

### Blue-Team Practical

Find containers with added capabilities.

```bash
docker ps -q | while read id; do
  name=$(docker inspect -f '{{.Name}}' "$id")
  caps=$(docker inspect -f '{{json .HostConfig.CapAdd}}' "$id")
  echo "$name $caps"
done
```

Review Compose files.

```bash
grep -R "NET_ADMIN\|NET_RAW\|privileged" . || true
```

Observation: capability review clearly shows which containers have added capabilities or privileged mode.

Defensive interpretation: debug and VPN containers need special scrutiny because they often require powerful network capabilities.

---
