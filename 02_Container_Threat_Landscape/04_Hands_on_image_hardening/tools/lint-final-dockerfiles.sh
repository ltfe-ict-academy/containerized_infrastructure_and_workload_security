#!/usr/bin/env bash
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lab_dir="$(cd "${script_dir}/.." && pwd)"

files=(
  "example_app_final/backend/Dockerfile"
  "example_app_final/frontend/Dockerfile"
)

status=0
for file in "${files[@]}"; do
  file_path="${lab_dir}/${file}"

  echo "== hadolint: ${file} =="
  if command -v hadolint >/dev/null 2>&1; then
    hadolint "${file_path}" || status=1
  else
    sudo docker run --rm -i hadolint/hadolint < "${file_path}" || status=1
  fi

  echo "== checkov: ${file} =="
  # Example for the image-only lab if HEALTHCHECK is intentionally deferred:
  # CHECKOV_EXTRA_ARGS="--skip-check CKV_DOCKER_2" ./tools/lint-starting-dockerfiles.sh
  if command -v checkov >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    checkov -f "${file_path}" --framework dockerfile ${CHECKOV_EXTRA_ARGS:-} || status=1
  else
    docker_tty_args=()
    if [[ -t 1 ]]; then
      docker_tty_args=(--tty)
    fi

    # shellcheck disable=SC2086
    sudo docker run "${docker_tty_args[@]}" --rm \
      --volume "${lab_dir}:/tf" \
      --workdir /tf \
      bridgecrew/checkov \
      -f "${file}" --framework dockerfile ${CHECKOV_EXTRA_ARGS:-} || status=1
  fi
  echo
done

exit "${status}"
