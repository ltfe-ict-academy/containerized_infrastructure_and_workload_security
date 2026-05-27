#!/bin/sh
set -e

# Validate required env vars
if [ -z "$DOCKHAND_AUTH_USER" ] || [ -z "$DOCKHAND_AUTH_PASSWORD" ]; then
  echo "ERROR: DOCKHAND_AUTH_USER and DOCKHAND_AUTH_PASSWORD must be set." >&2
  exit 1
fi

# Generate htpasswd file from env vars (bcrypt, cost 12)
htpasswd -cbB -C 12 /etc/nginx/.htpasswd "$DOCKHAND_AUTH_USER" "$DOCKHAND_AUTH_PASSWORD"
chown root:nginx /etc/nginx/.htpasswd
chmod 640 /etc/nginx/.htpasswd

echo "Basic auth configured for user: $DOCKHAND_AUTH_USER"

exec nginx -g "daemon off;"
