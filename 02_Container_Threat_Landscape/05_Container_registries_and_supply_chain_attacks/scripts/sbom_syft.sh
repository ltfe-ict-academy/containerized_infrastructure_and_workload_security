#!/usr/bin/env bash
# Generate SBOMs in the three formats you will see in the wild:
#   SPDX 2.3 JSON     (ISO/IEC 5962, default for many gov / regulated)
#   CycloneDX 1.5     (OWASP, default in many security tools)
#   Syft native JSON  (richest format, but Anchore-specific)
#
# Usage:  ./sbom_syft.sh <image[:tag]> <output-dir>
# Example: ./sbom_syft.sh node:22-alpine sboms/node-22-alpine

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <image[:tag]> <output-dir>"
    exit 2
fi

IMAGE="$1"
OUT_DIR="$2"

mkdir -p "$OUT_DIR"

echo "==> syft $IMAGE -> SPDX 2.3 JSON"
syft "$IMAGE" -o spdx-json="$OUT_DIR/spdx.json"

echo "==> syft $IMAGE -> CycloneDX 1.5 JSON"
syft "$IMAGE" -o cyclonedx-json="$OUT_DIR/cyclonedx.json"

echo "==> syft $IMAGE -> Syft native JSON"
syft "$IMAGE" -o syft-json="$OUT_DIR/syft.json"

echo
echo "Wrote SBOMs to $OUT_DIR/"
ls -lh "$OUT_DIR"
