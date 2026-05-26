#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 -r <registry> [-v <version>] [-p <platform>]"
  echo "  -r  Registry prefix (e.g. registry.example.com/course)  [required]"
  echo "  -v  Image version tag                                    [default: 1.0.0]"
  echo "  -p  Build platform                                       [default: linux/amd64]"
  exit 1
}

REGISTRY=""
VERSION="1.0.0"
PLATFORM="linux/amd64"

while getopts ":r:v:p:" opt; do
  case "${opt}" in
    r) REGISTRY="${OPTARG}" ;;
    v) VERSION="${OPTARG}" ;;
    p) PLATFORM="${OPTARG}" ;;
    *) usage ;;
  esac
done

[[ -z "${REGISTRY}" ]] && { echo "Error: -r <registry> is required."; usage; }

# SBOM/provenance attestations are most useful when attached to pushed image artifacts.
sudo docker buildx build \
  --platform "${PLATFORM}" \
  --sbom=true \
  --provenance=true \
  --build-arg UV_VERSION=0.11.15 \
  --build-arg UV_INDEX_URL="${UV_INDEX_URL:-https://pypi.org/simple}" \
  --build-arg APP_UID=10001 \
  --build-arg APP_GID=10001 \
  -t "${REGISTRY}/course-backend:${VERSION}" \
  --push ./example_app_final/backend

sudo docker buildx build \
  --platform "${PLATFORM}" \
  --sbom=true \
  --provenance=true \
  --build-arg VITE_API_BASE_URL="${VITE_API_BASE_URL:-/api}" \
  -t "${REGISTRY}/course-frontend:${VERSION}" \
  --push ./example_app_final/frontend
