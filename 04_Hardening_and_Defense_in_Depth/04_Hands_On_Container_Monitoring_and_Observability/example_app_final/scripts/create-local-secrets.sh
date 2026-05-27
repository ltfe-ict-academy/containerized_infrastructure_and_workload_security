#!/usr/bin/env sh
set -eu

mkdir -p secrets

create_secret() {
  path="$1"
  label="$2"

  if [ -f "$path" ]; then
    echo "Keeping existing $path"
    return
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 > "$path"
  else
    umask 022
    dd if=/dev/urandom bs=32 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n' > "$path"
    printf '\n' >> "$path"
  fi

  # Local Docker Compose file-backed secrets are mounted from host files.
  # World-readability keeps this lab runnable with non-root containers.
  # Treat the generated files as local lab credentials and never commit them.
  chmod 0444 "$path"
  echo "Created $label at $path"
}

create_secret secrets/postgres_password.txt "PostgreSQL password"
create_secret secrets/redis_password.txt "Redis password"

ACL_DEST="secrets/redis_users.acl"
ACL_SRC="secrets/redis_users.acl.example"
if [ -f "$ACL_DEST" ]; then
  echo "Keeping existing $ACL_DEST"
else
  redis_pw=$(tr -d '\n' < secrets/redis_password.txt)
  sed "s|YOUR_REDIS_PASSWORD_HERE|${redis_pw}|" "$ACL_SRC" > "$ACL_DEST"
  chmod 0444 "$ACL_DEST"
  echo "Created Redis ACL file at $ACL_DEST"
fi

echo "Local secrets are ready. Start the stack with: docker compose up --build"
