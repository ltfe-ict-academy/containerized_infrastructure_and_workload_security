# syntax=docker/dockerfile:1.10

FROM node:24-bookworm-slim@sha256:24dc26ef1e3c3690f27ebc4136c9c186c3133b25563ae4d7f0692e4d1fe5db0e AS build

ARG VITE_API_BASE_URL=/api
ENV VITE_API_BASE_URL=${VITE_API_BASE_URL}

WORKDIR /src

COPY package.json package-lock.json ./

RUN --mount=type=cache,target=/root/.npm \
    npm ci --ignore-scripts --no-audit --no-fund

COPY index.html ./index.html
COPY src ./src

RUN npm run build

# Final stage: Use a minimal nginx image to serve the built application
FROM dhi.io/nginx:1.31.0-debian13@sha256:07477e2829f4f800abcdf369a93c9e5ec5dc4b17b2b86deb44063414aec3cd16 AS runtime

COPY --from=build --chown=65532:65532 /src/dist /usr/share/nginx/html

USER 65532:65532

EXPOSE 8080
