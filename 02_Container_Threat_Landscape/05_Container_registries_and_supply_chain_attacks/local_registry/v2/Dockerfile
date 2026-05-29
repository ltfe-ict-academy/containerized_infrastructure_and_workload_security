# The "bad" payments image — version 2, same tag.
#
# In a real tag-swap incident the attacker tries to make the malicious
# version look identical to the legitimate one. The point of this lab
# is not the payload — it is the fact that the same registry path
# (localhost:5000/internal/payments:prod) can resolve to two different
# images at two different times.
#
# So we keep the banner exactly the same and append one extra line
# that is the marker of "this is the wrong image". In a real attack
# that line would be replaced by something that quietly phones home.

FROM alpine:3.20

LABEL org.opencontainers.image.title="payments"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.description="Internal payments service (clean build)"

# The marker — would normally be a curl-and-pipe-to-shell, a coin
# miner, or a reverse shell. We just print a line.
CMD ["sh", "-c", "echo 'payments service starting...'; echo '[backdoor] hello from the malicious version'; sleep 5; echo 'payments service ready'"]
