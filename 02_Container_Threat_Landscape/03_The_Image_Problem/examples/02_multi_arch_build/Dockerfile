# syntax=docker/dockerfile:1

# Pin the build environment to the native host platform to ensure the compiler runs at full speed
FROM --platform=$BUILDPLATFORM golang:1.23-alpine AS builder
WORKDIR /src

# Copy source code
COPY . .

# Capture target architecture variables supplied by BuildKit
ARG TARGETOS
ARG TARGETARCH

# Cross-compile the Go binary using native hardware instead of slow QEMU emulation
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /app/server .

# Deployment stage
FROM alpine:3.20
WORKDIR /app
COPY --from=builder /app/server .

CMD ["./server"]
