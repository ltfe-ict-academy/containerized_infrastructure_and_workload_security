#!/usr/bin/env bash
# Opinionated trivy invocation for the workshop.
#
# Usage:
#   ./scan_trivy.sh <image[:tag]>            # human-readable table
#   ./scan_trivy.sh <image[:tag]> sarif      # emit results.sarif for CI
#   ./scan_trivy.sh <image[:tag]> json       # emit results.json (raw)
#
# Examples:
#   ./scan_trivy.sh node:14.17.0
#   ./scan_trivy.sh node:22-alpine sarif
#
# Flag notes:
#   --severity MEDIUM,HIGH,CRITICAL  show only what matters first
#   --ignore-unfixed                 hide CVEs with no available patch
#                                    (useful for triage; toggle off later)
#   --scanners vuln,secret,misconfig also scan for embedded secrets
#                                    and dockerfile misconfigurations
#   --quiet                          suppress progress noise

set -euo pipefail

if [[ $# -lt 1 ]]; then
    cat <<USAGE
Usage: $0 <image[:tag]> [table|sarif|json]

Default output is a human-readable table. Pass 'sarif' or 'json' for
machine-consumable formats (the GitHub Actions / GitLab CI path).
USAGE
    exit 2
fi

IMAGE="$1"
FORMAT="${2:-table}"

mkdir -p scans
SAFE_NAME="$(echo "$IMAGE" | tr '/:' '__')"

COMMON_ARGS=(
    --quiet
    --severity MEDIUM,HIGH,CRITICAL
    --ignore-unfixed
    --scanners vuln,secret,misconfig
)

case "$FORMAT" in
    table)
        OUT="scans/trivy-${SAFE_NAME}.txt"
        echo "==> trivy image ($IMAGE) — human-readable"
        trivy image "${COMMON_ARGS[@]}" --format table "$IMAGE" | tee "$OUT"
        ;;
    sarif)
        OUT="scans/trivy-${SAFE_NAME}.sarif"
        echo "==> trivy image ($IMAGE) — SARIF for CI"
        trivy image "${COMMON_ARGS[@]}" --format sarif --output "$OUT" "$IMAGE"
        echo "Findings: $(jq '.runs[0].results | length' "$OUT")"
        ;;
    json)
        OUT="scans/trivy-${SAFE_NAME}.json"
        echo "==> trivy image ($IMAGE) — raw JSON"
        trivy image "${COMMON_ARGS[@]}" --format json --output "$OUT" "$IMAGE"
        ;;
    *)
        echo "Unknown format: $FORMAT (use table|sarif|json)"
        exit 2
        ;;
esac

echo
echo "Saved to: $OUT"
