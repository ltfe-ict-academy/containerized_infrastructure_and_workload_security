#!/usr/bin/env bash
set -euo pipefail

EXT_IF="${1:-eth0}"
WEB_PORT="${2:-8080}"
MGMT_CIDR="${3:-192.0.2.0/24}"

CHAIN="COURSE_DOCKER_EDGE"

iptables -N "${CHAIN}" 2>/dev/null || true
iptables -F "${CHAIN}"

iptables -C DOCKER-USER -j "${CHAIN}" 2>/dev/null || iptables -I DOCKER-USER 1 -j "${CHAIN}"

iptables -A "${CHAIN}" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A "${CHAIN}" -i "${EXT_IF}" -p tcp --dport "${WEB_PORT}" -j ACCEPT
iptables -A "${CHAIN}" -i "${EXT_IF}" -s "${MGMT_CIDR}" -p tcp -m multiport --dports 22,3000,9090 -j ACCEPT
iptables -A "${CHAIN}" -i "${EXT_IF}" -p tcp -m multiport --dports 5432,6379,8000 -j DROP
iptables -A "${CHAIN}" -j RETURN

echo "Applied Docker-aware rules in DOCKER-USER via chain ${CHAIN}"
