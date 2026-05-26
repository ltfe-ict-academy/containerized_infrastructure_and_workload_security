#!/usr/bin/env bash
set -euo pipefail

mkdir -p reports
images=(
#   "course/backend:starting"
#   "course/frontend:starting"
  "course/backend:final"
  "course/frontend:final"
)

for image in "${images[@]}"; do
  safe_name="${image//\//_}"
  safe_name="${safe_name//:/_}"

  echo "== Trivy image scan: ${image} =="
  sudo trivy image --scanners vuln,secret,misconfig --format table "${image}" \
    | tee "reports/${safe_name}.trivy.txt"

  echo "== Grype image scan: ${image} =="
  sudo grype "${image}" -o table \
    | tee "reports/${safe_name}.grype.txt"

  echo "== Syft SBOMs: ${image} =="
  sudo syft "${image}" -o cyclonedx-json="reports/${safe_name}.cdx.json"
  sudo syft "${image}" -o spdx-json="reports/${safe_name}.spdx.json"

  echo "== Scan generated SBOM with Trivy: ${image} =="
  sudo trivy sbom "reports/${safe_name}.cdx.json" \
    | tee "reports/${safe_name}.trivy-sbom.txt"

  echo "== Scan generated SBOM with Grype: ${image} =="
  sudo grype "sbom:reports/${safe_name}.cdx.json" -o table \
    | tee "reports/${safe_name}.grype-sbom.txt"

  echo
done
