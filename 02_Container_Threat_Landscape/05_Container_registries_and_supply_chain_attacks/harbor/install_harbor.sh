#!/usr/bin/env bash
# Deploy Harbor for Lab 6, loopback-only.
#
# WHY THIS IS NOT JUST `hostname: 127.0.0.1`:
# Harbor's config validator literally rejects "127.0.0.1" and "localhost"
# as hostnames — the rationale is that the hostname becomes part of every
# image reference Harbor serves, and clients across a network would not
# be able to resolve it. The trick: use a fake hostname (default
# "harbor.local") and add it to /etc/hosts pointing at 127.0.0.1.
# Harbor accepts the name, every client resolves it to loopback, and
# the registry stays off the network.
#
# WHY WE EDIT docker-compose.yml:
# By default, Harbor's generated compose publishes its ports on 0.0.0.0,
# i.e. every interface. We rewrite it to bind 127.0.0.1 only so that
# even on a multi-homed VM the registry is not reachable from outside.
# Access from your laptop is via SSH local-forward, e.g.:
#   ssh -L 8080:127.0.0.1:8080 user@vm
#
# This script:
#   1. Picks a hostname (default harbor.local), ensures /etc/hosts has it
#   2. Downloads + extracts the Harbor offline installer
#   3. Generates harbor.yml (HTTP only, port 8080)
#   4. Loads Harbor's images, runs ./prepare
#   5. Rewrites the generated docker-compose.yml to bind ports to 127.0.0.1
#   6. Runs docker compose up -d
#   7. Optionally configures Docker's insecure-registries
#   8. Prints the SSH tunnel + login instructions

set -euo pipefail

# --- knobs --------------------------------------------------------
HARBOR_VERSION="${HARBOR_VERSION:-v2.15.1}"
HARBOR_HOST="${HARBOR_HOST:-harbor.local}"
HARBOR_PORT="${HARBOR_PORT:-8080}"
HARBOR_PASSWORD="${HARBOR_PASSWORD:-Harbor12345}"

# Set CONFIGURE_DOCKER=yes to automatically add this Harbor to Docker's
# insecure-registries list and restart the daemon. Default 'no'.
CONFIGURE_DOCKER="${CONFIGURE_DOCKER:-no}"

# --- sanity -------------------------------------------------------
if [[ "$HARBOR_HOST" == "127.0.0.1" || "$HARBOR_HOST" == "localhost" ]]; then
    echo "ERROR: Harbor refuses '127.0.0.1' and 'localhost' as hostnames."
    echo "       Use a fake name like 'harbor.local' (the default)."
    echo "       /etc/hosts will be configured to resolve it to 127.0.0.1."
    exit 1
fi
if ! command -v sudo >/dev/null; then
    echo "ERROR: sudo is required."
    exit 1
fi

WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$WORK_DIR"

echo "==> Harbor will be reachable on the VM at:"
echo "      http://${HARBOR_HOST}:${HARBOR_PORT}"
echo "    (loopback only — bind to 127.0.0.1)"
echo

# --- ensure /etc/hosts entry -------------------------------------
if ! grep -qE "^[[:space:]]*127\.0\.0\.1[[:space:]].*\<${HARBOR_HOST}\>" /etc/hosts; then
    echo "==> Adding '${HARBOR_HOST}' to /etc/hosts (-> 127.0.0.1)"
    echo "127.0.0.1 ${HARBOR_HOST}" | sudo tee -a /etc/hosts >/dev/null
else
    echo "==> /etc/hosts already has an entry for ${HARBOR_HOST}, leaving it alone"
fi

# --- download + extract installer --------------------------------
if [[ -d harbor ]]; then
    echo "==> harbor/ directory already exists; reusing"
else
    echo "==> Downloading Harbor ${HARBOR_VERSION} (~700 MB)..."
    curl -fL -o harbor.tgz \
        "https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/harbor-offline-installer-${HARBOR_VERSION}.tgz"
    echo "==> Extracting..."
    tar -xzf harbor.tgz
    rm harbor.tgz
fi

cd harbor

# --- generate harbor.yml -----------------------------------------
if [[ ! -f harbor.yml ]]; then
    echo "==> Generating workshop harbor.yml..."
    cp harbor.yml.tmpl harbor.yml

    sed -i "s|^hostname:.*|hostname: ${HARBOR_HOST}|" harbor.yml
    sed -i "s|^  port: 80$|  port: ${HARBOR_PORT}|" harbor.yml
    sed -i "s|^harbor_admin_password:.*|harbor_admin_password: ${HARBOR_PASSWORD}|" harbor.yml

    # Comment out the entire https: block — no cert in the workshop.
    python3 - <<'PY'
import re
with open('harbor.yml') as f:
    content = f.read()
content = re.sub(
    r'^https:\n(?:  .*\n)+',
    '# https: disabled for workshop — use HTTPS in production.\n',
    content,
    flags=re.MULTILINE,
)
with open('harbor.yml', 'w') as f:
    f.write(content)
PY
fi

# --- step through what install.sh would do, with our edits -------
echo "==> Loading Harbor images..."
IMG_TARBALL="$(ls harbor.*.tar.gz 2>/dev/null | head -n1)"
if [[ -n "$IMG_TARBALL" ]]; then
    sudo docker load -i "$IMG_TARBALL"
else
    echo "WARN: no harbor.*.tar.gz found — relying on remote pulls"
fi

echo "==> Running ./prepare to generate docker-compose.yml + configs..."
sudo ./prepare

# --- bind published ports to 127.0.0.1 ---------------------------
# Harbor's prepare step writes ./docker-compose.yml with a 'proxy'
# service whose ports look like:
#     ports:
#       - 8080:8080/tcp
# We rewrite that to bind on loopback only.
COMPOSE_FILE="docker-compose.yml"
if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "ERROR: $COMPOSE_FILE not found after prepare — aborting."
    exit 1
fi

echo "==> Rewriting $COMPOSE_FILE to bind ports to 127.0.0.1 only..."
sudo cp "$COMPOSE_FILE" "${COMPOSE_FILE}.before-loopback-edit"

# Match any "- <port>:<port>/tcp" published port line and prefix
# the host side with 127.0.0.1:. Handles both quoted and unquoted forms.
sudo python3 - "$COMPOSE_FILE" <<'PY'
import re, sys

path = sys.argv[1]
with open(path) as f:
    text = f.read()

# Lines that look like port publications under 'ports:' blocks.
# Examples we want to rewrite:
#     - 8080:8080/tcp
#     - "8080:8080"
#     - 4443:4443/tcp
# Leave anything that already binds to an explicit IP alone.
def rewrite(line):
    m = re.match(r'(\s*-\s*)"?(\d+):(\d+)(/\w+)?"?\s*$', line)
    if not m:
        return line
    indent, host_port, ctr_port, proto = m.groups()
    proto = proto or ""
    return f'{indent}"127.0.0.1:{host_port}:{ctr_port}{proto}"\n'

out = []
in_ports = False
ports_indent = None
for line in text.splitlines(keepends=True):
    stripped = line.rstrip("\n")
    if re.match(r'^\s*ports:\s*$', stripped):
        in_ports = True
        ports_indent = len(stripped) - len(stripped.lstrip())
        out.append(line)
        continue
    if in_ports:
        # If line is more indented than 'ports:', we're still inside.
        cur_indent = len(line) - len(line.lstrip())
        if line.strip() == "":
            out.append(line); continue
        if cur_indent <= ports_indent:
            in_ports = False
            out.append(line); continue
        out.append(rewrite(line))
    else:
        out.append(line)

with open(path, "w") as f:
    f.writelines(out)
PY

echo "==> Port bindings after rewrite:"
grep -nE '"127\.0\.0\.1:' "$COMPOSE_FILE" || {
    echo "WARN: no 127.0.0.1 bindings found — the rewrite may have missed."
    echo "      Diff against ${COMPOSE_FILE}.before-loopback-edit to investigate."
}

# --- optionally configure docker insecure-registries ------------
configure_docker_insecure() {
    local target="${HARBOR_HOST}:${HARBOR_PORT}"
    echo "==> Adding ${target} to Docker's insecure-registries list..."
    sudo mkdir -p /etc/docker

    if [[ -s /etc/docker/daemon.json ]]; then
        sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%s)
        sudo bash -c "
            jq --arg t '${target}' '
                .\"insecure-registries\" = ((.\"insecure-registries\" // []) + [\$t] | unique)
            ' /etc/docker/daemon.json > /etc/docker/daemon.json.new \
            && mv /etc/docker/daemon.json.new /etc/docker/daemon.json
        "
    else
        echo "{\"insecure-registries\": [\"${target}\"]}" \
            | sudo tee /etc/docker/daemon.json >/dev/null
    fi

    echo "==> Restarting Docker..."
    sudo systemctl restart docker
}

if [[ "$CONFIGURE_DOCKER" == "yes" ]]; then
    if ! command -v jq >/dev/null; then
        echo "ERROR: jq not found; install with 'sudo apt-get install -y jq'"
        echo "       (or re-run with CONFIGURE_DOCKER=no and configure by hand)"
        exit 1
    fi
    configure_docker_insecure
fi

# --- start harbor ------------------------------------------------
echo "==> Starting Harbor (docker compose up -d)..."
sudo docker compose up -d

# --- final guidance ----------------------------------------------
HARBOR_URL="http://${HARBOR_HOST}:${HARBOR_PORT}"

cat <<EOF

================================================================
Harbor is up — loopback only.

  URL on this VM:   ${HARBOR_URL}
  User:             admin
  Password:         ${HARBOR_PASSWORD}

  Listening on:     127.0.0.1:${HARBOR_PORT} (and 127.0.0.1:4443 for cert API)
                    NOT reachable from the LAN.

EOF

if [[ "$CONFIGURE_DOCKER" != "yes" ]]; then
cat <<EOF
NEXT — tell Docker this registry is HTTP-only
----------------------------------------------------------------
Either re-run with CONFIGURE_DOCKER=yes, or add by hand:

  sudo mkdir -p /etc/docker
  echo '{"insecure-registries": ["${HARBOR_HOST}:${HARBOR_PORT}"]}' \\
      | sudo tee /etc/docker/daemon.json
  sudo systemctl restart docker

If /etc/docker/daemon.json already exists, MERGE the key — don't
overwrite.

EOF
fi

cat <<EOF
ACCESSING HARBOR FROM YOUR LAPTOP (SSH tunnel)
----------------------------------------------------------------
From your laptop:

  ssh -L ${HARBOR_PORT}:127.0.0.1:${HARBOR_PORT} <user>@<this-vm>

Then on your laptop, add to /etc/hosts (or %WINDIR%\\System32\\drivers\\etc\\hosts):

  127.0.0.1 ${HARBOR_HOST}

Now you can open ${HARBOR_URL} in your laptop browser, and
'docker pull ${HARBOR_HOST}:${HARBOR_PORT}/...' on your laptop
also goes through the tunnel.

LAB 6 WALKTHROUGH
----------------------------------------------------------------
1. Open ${HARBOR_URL}.
2. Create a private project named 'payments'.
3. Project Configuration -> Deployment security -> Cosign (enable).
4. Project Configuration -> Vulnerability scanning -> set threshold.
5. Tag immutability -> New rule, pattern '**', retention 'always'.
6. System -> Robot Accounts -> create one scoped to 'payments'.
7. Push an image:

     docker login ${HARBOR_HOST}:${HARBOR_PORT} -u 'robot\$payments+ci'
     docker tag <existing-image> ${HARBOR_HOST}:${HARBOR_PORT}/payments/payments:v1.0.0
     docker push ${HARBOR_HOST}:${HARBOR_PORT}/payments/payments:v1.0.0
================================================================
EOF
