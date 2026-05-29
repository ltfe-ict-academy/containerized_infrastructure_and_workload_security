#!/usr/bin/env bash
# Opinionated grype invocation for the workshop.
#
# Usage:
#   ./scan_grype.sh <image | sbom:path>           # table
#   ./scan_grype.sh <image | sbom:path> sarif     # SARIF for CI
#   ./scan_grype.sh <image | sbom:path> json      # raw Grype JSON
#
# Examples:
#   ./scan_grype.sh node:14.17.0
#   ./scan_grype.sh sbom:sboms/node-22-alpine/syft.json sarif
#
# Flag notes:
#   --only-fixed     hide CVEs with no available patch (mirror of trivy's
#                    --ignore-unfixed; first-triage default)
#   --fail-on critical exits non-zero on critical findings — useful as a
#                    CI gate but disabled here so the workshop demo doesn't
#                    fail with a stack of exits.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    cat <<USAGE
Usage: $0 <image[:tag] | sbom:path> [table|sarif|json]

Grype accepts either a container reference (it will pull/scan) or a
pre-generated SBOM as 'sbom:path/to/sbom.json'. SBOM input is faster and
more deterministic — that's the canonical CI path.
USAGE
    exit 2
fi

TARGET="$1"
FORMAT="${2:-table}"

mkdir -p scans
SAFE_NAME="$(echo "$TARGET" | tr '/:' '__')"

case "$FORMAT" in
    table)
        OUT="scans/grype-${SAFE_NAME}.txt"
        echo "==> grype ($TARGET) — human-readable"
        grype "$TARGET" --only-fixed --output table | tee "$OUT"
        ;;
    sarif)
        OUT="scans/grype-${SAFE_NAME}.sarif"
        echo "==> grype ($TARGET) — SARIF for CI"
        grype "$TARGET" --only-fixed --output sarif --file "$OUT"
        echo "Findings: $(jq '.runs[0].results | length' "$OUT")"
        ;;
    json)
        OUT="scans/grype-${SAFE_NAME}.json"
        echo "==> grype ($TARGET) — raw JSON"
        grype "$TARGET" --only-fixed --output json --file "$OUT"
        ;;
    *)
        echo "Unknown format: $FORMAT (use table|sarif|json)"
        exit 2
        ;;
esac

echo
echo "Saved to: $OUT"
