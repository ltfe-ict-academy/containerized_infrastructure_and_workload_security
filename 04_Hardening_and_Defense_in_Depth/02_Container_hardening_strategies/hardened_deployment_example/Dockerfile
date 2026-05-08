# syntax=docker/dockerfile:1

############################
# Build / dependency stage #
############################
FROM node:22-bookworm-slim AS deps

WORKDIR /app

# Copy dependency manifests first for better caching.
COPY package*.json ./

# Use BuildKit secret for private npm token.
# Build with:
#   DOCKER_BUILDKIT=1 docker build \
#     --secret id=npm_token,src=.npm_token \
#     -t myapp:secure .
RUN --mount=type=secret,id=npm_token,required=false \
    set -eu; \
    if [ -f /run/secrets/npm_token ]; then \
      echo "//registry.npmjs.org/:_authToken=$(cat /run/secrets/npm_token)" > .npmrc; \
    fi; \
    npm ci --omit=dev; \
    rm -f .npmrc; \
    npm cache clean --force

#################
# Runtime image #
#################
FROM node:22-bookworm-slim AS runtime

ENV NODE_ENV=production

WORKDIR /app

# Create fixed non-root UID/GID.
# Avoid relying on a named user that may differ across images.
RUN groupadd --system --gid 10001 appgroup \
 && useradd --system --uid 10001 --gid appgroup --home-dir /app --shell /usr/sbin/nologin appuser

# Copy only what is required to run.
COPY --from=deps --chown=10001:10001 /app/node_modules ./node_modules
COPY --chown=10001:10001 package*.json ./
COPY --chown=10001:10001 src ./src

# Optional: make application files non-writable.
# The container should write only to tmpfs or explicit volumes.
RUN chmod -R go-w /app

USER 10001:10001

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["node", "src/server.js"]