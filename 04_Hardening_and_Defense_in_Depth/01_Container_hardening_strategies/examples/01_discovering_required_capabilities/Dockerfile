FROM debian:bookworm-slim AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY main.c .
RUN gcc -O2 -Wall -Wextra -o cap-demo main.c

FROM debian:bookworm-slim

RUN groupadd -g 10001 appuser \
    && useradd -u 10001 -g 10001 -M -s /usr/sbin/nologin appuser

COPY --from=build /src/cap-demo /usr/local/bin/cap-demo

ENTRYPOINT ["/usr/local/bin/cap-demo"]
