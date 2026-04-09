A good **Defend The Flag** for this course is a **single misconfigured VM running a Docker Compose stack**. That lets participants touch almost every topic from the week: images, runtime security, Linux/container networking, secrets, logging, and host hardening. Compose is also a practical fit because Docker documents first-class support for Compose networking and secrets, while mainstream hardening guidance for containers emphasizes non-root execution, least privilege, restricted capabilities, seccomp/AppArmor, minimal exposure, and safer secret handling. ([Docker Documentation][1])

## Challenge concept

Build a scenario like this:

* **public reverse proxy** (`nginx` or `traefik`)
* **frontend web app**
* **backend API**
* **Postgres**
* **Redis**
* **optional “admin” container** that should never be public
* **optional monitoring** (`prometheus` + `node-exporter` or just a simple metrics endpoint)

The starting state is “works, but dangerously.” The participants win only if the application **still works** after they harden it. That mirrors real operations better than a pure break/fix lab.

## What to misconfigure on purpose

I would seed 10–14 issues, with a mix of easy, medium, and “stretch” fixes.

### 1) Runtime hardening issues

* Containers run as `root`
* `privileged: true` on at least one service
* extra Linux capabilities added, especially something like `SYS_ADMIN`
* no `no-new-privileges`
* writable root filesystem
* `/var/run/docker.sock` mounted into the app
* broad host bind mounts like `/` or `/etc`
* no healthchecks

These are exactly the kinds of risky defaults and exceptions that OWASP and Docker security guidance warn about. Docker’s seccomp docs also note that the default profile is a moderate allowlist, so dropping to `unconfined` or over-privileging containers makes a good teaching trap. ([OWASP Cheat Sheet Series][2])

### 2) Image and supply-chain issues

* `image: something:latest`
* intentionally old/vulnerable base image
* bloated image with tools that attackers love (`curl`, `bash`, package managers, compilers)
* secret copied into image during build
* `.env` committed with real-looking passwords
* no image pinning or provenance checks

Docker’s build guidance recommends trusted, regularly updated base images and smaller, more maintainable builds, including multi-stage builds where useful. OWASP’s secret management guidance also explicitly warns against hardcoded plaintext secrets in source/config. ([Docker Documentation][3])

### 3) Networking issues

* database port published to `0.0.0.0`
* Redis publicly reachable
* admin UI exposed externally
* flat single Docker network for every service
* overly broad host firewall rules
* Docker daemon exposed on TCP, especially insecurely
* app can initiate outbound traffic anywhere

Docker documents Compose networking and the Docker daemon attack surface; Kubernetes security guidance similarly treats workload isolation and network controls as core defenses. For a single-VM challenge, that translates nicely to private/internal Compose networks plus host firewall rules. ([Docker Documentation][1])

### 4) Host hardening and ops issues

* Docker daemon listening on `2375`
* no log rotation
* world-readable secret files on disk
* SSH too open, maybe password auth enabled
* missing systemd restart settings
* weak file permissions on deployment artifacts

Docker’s docs warn that the daemon is highly privileged and should only be controlled by trusted users; Docker also notes that the default `json-file` driver performs no log rotation by default, and recommends safer logging configuration to avoid disk exhaustion. ([Docker Documentation][4])

## What participants should have to achieve

A clean target state could be:

* app reachable on `80/443`
* database and Redis **not** reachable from outside
* admin service only on an internal network or localhost tunnel
* all app containers run as non-root
* no privileged containers
* no extra caps unless explicitly justified
* `no-new-privileges:true`
* read-only root filesystem where possible
* `tmpfs` for writable temp dirs if needed
* no `docker.sock` mount
* secrets moved out of env files into mounted secrets
* healthchecks added
* sensible restart policies
* basic logging and log rotation configured
* optional bonus: daemon hardened with `userns-remap` or rootless mode

Running the daemon rootless, or remapping container root to a less privileged host user, is directly supported by Docker and makes a strong bonus objective without making it mandatory for a 4-hour lab. ([Docker Documentation][5])

## Best structure for a 4-hour capstone

Use a points system so teams can make progress even if they do not finish everything.

### Suggested scoring

* **20 pts** availability still works
* **20 pts** public exposure fixed
* **20 pts** container runtime hardening
* **15 pts** secrets fixed
* **10 pts** image/build cleanup
* **10 pts** logging/observability
* **5 pts** stretch bonus: rootless or `userns-remap`

That gives them multiple paths to partial credit and keeps the exercise from turning into one giant blocker.

## Make the checker enforce “secure and still functional”

The easiest failure mode in these exercises is that participants just stop services or firewall everything. Your checker should therefore verify both:

1. **availability**
2. **hardening**

That means tests like:

* `curl http://host/health` returns 200
* database port 5432 is **not** listening publicly
* admin UI is **not** public
* containers are not root/privileged
* no docker socket mount
* secrets are not exposed as env vars
* log rotation exists
* healthchecks exist

## A practical checker script

Below is a solid starter in Bash. It assumes:

* the project name is `dtf`
* service names are `proxy`, `frontend`, `api`, `db`, `redis`, `admin`
* `jq`, `curl`, `ss`, and Docker are available

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-dtf}"
HOST="${HOST:-127.0.0.1}"
PASS=0
FAIL=0

ok()   { echo "[PASS] $*"; PASS=$((PASS+1)); }
bad()  { echo "[FAIL] $*"; FAIL=$((FAIL+1)); }
info() { echo "[INFO] $*"; }

cid() {
  docker ps -q \
    --filter "label=com.docker.compose.project=${PROJECT}" \
    --filter "label=com.docker.compose.service=$1" | head -n1
}

require_running() {
  local s="$1"
  local c
  c="$(cid "$s")"
  if [[ -n "${c}" ]]; then
    ok "service '$s' is running"
  else
    bad "service '$s' is not running"
  fi
}

check_http_health() {
  local url="$1"
  local code
  code="$(curl -ksS -o /dev/null -w "%{http_code}" "$url" || true)"
  if [[ "$code" == "200" ]]; then
    ok "health endpoint reachable: $url"
  else
    bad "health endpoint failed: $url (got ${code:-none})"
  fi
}

check_port_not_listening() {
  local port="$1"
  if ss -ltn "( sport = :$port )" | grep -q ":$port"; then
    bad "port $port is listening on the host"
  else
    ok "port $port is not listening on the host"
  fi
}

check_not_privileged() {
  local s="$1" c val
  c="$(cid "$s")"; [[ -n "$c" ]] || { bad "$s missing"; return; }
  val="$(docker inspect "$c" | jq -r '.[0].HostConfig.Privileged')"
  [[ "$val" == "false" ]] && ok "$s is not privileged" || bad "$s is privileged"
}

check_not_root() {
  local s="$1" c user
  c="$(cid "$s")"; [[ -n "$c" ]] || { bad "$s missing"; return; }
  user="$(docker inspect "$c" | jq -r '.[0].Config.User // ""')"
  if [[ -n "$user" && "$user" != "0" && "$user" != "root" ]]; then
    ok "$s runs as non-root ($user)"
  else
    bad "$s runs as root or user not explicitly set"
  fi
}

check_read_only_rootfs() {
  local s="$1" c val
  c="$(cid "$s")"; [[ -n "$c" ]] || { bad "$s missing"; return; }
  val="$(docker inspect "$c" | jq -r '.[0].HostConfig.ReadonlyRootfs')"
  [[ "$val" == "true" ]] && ok "$s has read-only root filesystem" || bad "$s root filesystem is writable"
}

check_no_new_privileges() {
  local s="$1" c
  c="$(cid "$s")"; [[ -n "$c" ]] || { bad "$s missing"; return; }
  if docker inspect "$c" | jq -e '.[0].HostConfig.SecurityOpt // [] | index("no-new-privileges:true")' >/dev/null; then
    ok "$s has no-new-privileges"
  else
    bad "$s missing no-new-privileges:true"
  fi
}

check_no_docker_sock_mount() {
  local s="$1" c
  c="$(cid "$s")"; [[ -n "$c" ]] || { bad "$s missing"; return; }
  if docker inspect "$c" | jq -e '.[0].Mounts[]? | select(.Source=="/var/run/docker.sock")' >/dev/null; then
    bad "$s mounts docker.sock"
  else
    ok "$s does not mount docker.sock"
  fi
}

check_no_cap_add() {
  local s="$1" c caps
  c="$(cid "$s")"; [[ -n "$c" ]] || { bad "$s missing"; return; }
  caps="$(docker inspect "$c" | jq -r '.[0].HostConfig.CapAdd | length // 0')"
  [[ "$caps" == "0" ]] && ok "$s has no added Linux capabilities" || bad "$s adds Linux capabilities"
}

check_healthcheck_present() {
  local s="$1" c
  c="$(cid "$s")"; [[ -n "$c" ]] || { bad "$s missing"; return; }
  if docker inspect "$c" | jq -e '.[0].Config.Healthcheck.Test' >/dev/null; then
    ok "$s has a healthcheck"
  else
    bad "$s missing a healthcheck"
  fi
}

check_secret_not_in_env() {
  local s="$1" pattern="$2" c
  c="$(cid "$s")"; [[ -n "$c" ]] || { bad "$s missing"; return; }
  if docker inspect "$c" | jq -r '.[0].Config.Env[]?' | grep -Eiq "$pattern"; then
    bad "$s exposes secret-like env var matching /$pattern/"
  else
    ok "$s does not expose secret-like env var matching /$pattern/"
  fi
}

check_secret_file_present() {
  local s="$1" path="$2" c
  c="$(cid "$s")"; [[ -n "$c" ]] || { bad "$s missing"; return; }
  if docker exec "$c" test -f "$path"; then
    ok "$s has secret file at $path"
  else
    bad "$s missing secret file at $path"
  fi
}

check_internal_network_only() {
  local s="$1" expected="$2" c
  c="$(cid "$s")"; [[ -n "$c" ]] || { bad "$s missing"; return; }
  if docker inspect "$c" | jq -e --arg net "$expected" '.[0].NetworkSettings.Networks | has($net)' >/dev/null; then
    ok "$s attached to expected network: $expected"
  else
    bad "$s not attached to expected network: $expected"
  fi
}

check_no_host_port() {
  local s="$1" port="$2" c
  c="$(cid "$s")"; [[ -n "$c" ]] || { bad "$s missing"; return; }
  if docker inspect "$c" | jq -e --arg p "${port}/tcp" '.[0].NetworkSettings.Ports[$p] != null' >/dev/null; then
    bad "$s publishes container port $port to host"
  else
    ok "$s does not publish container port $port"
  fi
}

check_docker_tcp_disabled() {
  if ss -ltn '( sport = :2375 or sport = :2376 )' | grep -Eq ':2375|:2376'; then
    bad "Docker daemon TCP socket is listening"
  else
    ok "Docker daemon TCP socket is not listening"
  fi
}

check_log_rotation() {
  if [[ -f /etc/docker/daemon.json ]] && jq -e '
      (.["log-driver"] == "local")
      or
      (.["log-opts"]["max-size"]? != null and .["log-opts"]["max-file"]? != null)
    ' /etc/docker/daemon.json >/dev/null 2>&1; then
    ok "Docker daemon log rotation configured"
  else
    bad "Docker daemon log rotation not configured"
  fi
}

echo "=== Availability ==="
require_running proxy
require_running frontend
require_running api
require_running db
require_running redis
check_http_health "http://${HOST}/health"

echo
echo "=== Public exposure ==="
check_port_not_listening 5432
check_port_not_listening 6379
check_port_not_listening 8081
check_docker_tcp_disabled

echo
echo "=== Runtime hardening ==="
for s in frontend api proxy; do
  check_not_privileged "$s"
  check_not_root "$s"
  check_read_only_rootfs "$s"
  check_no_new_privileges "$s"
  check_no_docker_sock_mount "$s"
  check_no_cap_add "$s"
  check_healthcheck_present "$s"
done

echo
echo "=== Secrets ==="
check_secret_not_in_env api 'PASS|PASSWORD|SECRET|TOKEN|KEY'
check_secret_file_present api '/run/secrets/db_password'

echo
echo "=== Networking ==="
check_internal_network_only db "${PROJECT}_backend"
check_no_host_port db 5432
check_no_host_port redis 6379

echo
echo "=== Operations ==="
check_log_rotation

echo
echo "=== Result ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [[ "$FAIL" -eq 0 ]]; then
  echo "STATUS: SUCCESS"
  exit 0
else
  echo "STATUS: FAILURE"
  exit 1
fi
```

## Why this checker design works

It checks **runtime reality**, not just files. That matters because participants can change Compose YAML without actually redeploying, or change host files without the containers picking them up. Using `docker inspect`, `ss`, and `curl` makes the score reflect the live system state.

## A nice extra twist

Add one or two “false friends”:

* a service that **must** keep one writable directory, so full read-only breaks it
* a service that genuinely needs one capability unless they redesign it
* a secret file with correct path but wrong permissions or wrong value

That forces them to understand the deployment instead of blindly copying hardening snippets.

## Suggested repo structure

```text
05_Defend_The_Flag/
├── README.md
├── scenario.md
├── deployment/
│   ├── compose.yaml
│   ├── .env.bad
│   ├── nginx/
│   ├── app/
│   └── db/
├── vm/
│   ├── provision.sh
│   ├── daemon.json.bad
│   └── firewall.bad.sh
├── checker/
│   ├── check.sh
│   └── expected.md
├── instructor/
│   ├── solution-notes.md
│   └── compose.hardened.example.yaml
└── scoring/
    └── rubric.md
```

## My recommendation

Keep the first version **Compose-based on one VM**, not Kubernetes-based. It is much easier to finish in 4 hours, still covers the whole week, and lets your checker stay simple and deterministic.

I can also turn this into a concrete `05_Defend_The_Flag/README.md` plus a full challenge spec with seeded misconfigurations, flags, scoring rubric, and an improved checker.

[1]: https://docs.docker.com/compose/how-tos/networking/?utm_source=chatgpt.com "Networking in Compose - Docker Docs"
[2]: https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html?utm_source=chatgpt.com "Docker Security - OWASP Cheat Sheet Series"
[3]: https://docs.docker.com/build/building/best-practices/?utm_source=chatgpt.com "Best practices | Docker Docs"
[4]: https://docs.docker.com/engine/security/?utm_source=chatgpt.com "Security | Docker Docs"
[5]: https://docs.docker.com/engine/security/rootless/?utm_source=chatgpt.com "Rootless mode | Docker Docs"




# IDEJE

- nardimo dashboard kjer udeleženci vidijo realtime stanje popravljenih zadev ne točno kaj amapk koliko točk samo imajo in koliko fixov so naredili
- lahko damo tudi nekakšen "leaderboard" ampak samo z točkami
- service na vmju preverja stanje in sporoča na api ki potem to prikazuje na dashboardu


# Implementation notes
- The backend service will be an API that calculate something based on the inputs and return the result. The result is saved in the database and some temp calcualation in redis. The API will be written in FastAPI.
