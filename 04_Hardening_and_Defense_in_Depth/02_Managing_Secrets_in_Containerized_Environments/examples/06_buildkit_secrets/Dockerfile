# syntax=docker/dockerfile:1

FROM alpine:3.20 AS build

# npm_token is mounted from a file into a custom target path.
# license_key is mounted from an environment variable into this RUN step only.
RUN --mount=type=secret,id=npm_token,target=/tmp/npm_token \
    --mount=type=secret,id=license_key,env=LICENSE_KEY \
    test -s /tmp/npm_token && \
    test -n "$LICENSE_KEY" && \
    mkdir -p /out && \
    printf "private dependency fetched without storing secrets\n" > /out/status.txt

FROM alpine:3.20
COPY --from=build /out/status.txt /app/status.txt
CMD ["cat", "/app/status.txt"]
