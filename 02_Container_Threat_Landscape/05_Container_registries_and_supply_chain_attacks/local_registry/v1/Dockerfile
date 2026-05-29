# The "good" payments image — version 1.
#
# Nothing interesting here. It exists so the tag-swap attack in Lab 1
# has a baseline that *looks* identical to the bad version from the
# outside (same name, same tag).

FROM alpine:3.20

LABEL org.opencontainers.image.title="payments"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.description="Internal payments service (clean build)"

CMD ["sh", "-c", "echo 'payments service starting...'; sleep 5; echo 'payments service ready'"]
