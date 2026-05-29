#!/usr/bin/env bash
# Verify a public Sigstore-signed image without setting up anything.
#
# We verify the cosign release image itself — the cosign project signs
# every release in CI using keyless OIDC, and the signatures are in
# the public Rekor transparency log.
#
# A note on the identity: many tutorials assume cosign is signed by a
# GitHub Actions workflow (issuer https://token.actions.githubusercontent.com).
# It is not. The Sigstore project releases via Google Cloud Build, so
# cosign images are signed by a GCP service account:
#   identity: keyless@projectsigstore.iam.gserviceaccount.com
#   issuer:   https://accounts.google.com
# These values are documented at https://docs.sigstore.dev/cosign/system_config/installation/
#
# This is itself a teaching moment for the workshop: when verification
# fails, cosign tells you what subject and issuer it *did* find. The
# fix is almost always "use those values" — or, if you didn't expect
# them, treat that as evidence the artifact isn't what you thought.

set -euo pipefail

# Pin the cosign release image to a specific version so the lab is
# reproducible. Bump this periodically.
TARGET_IMAGE="${TARGET_IMAGE:-ghcr.io/sigstore/cosign/cosign:v2.4.1}"

# The signing identity the Sigstore project uses for cosign releases.
SIGSTORE_IDENTITY="keyless@projectsigstore.iam.gserviceaccount.com"
SIGSTORE_ISSUER="https://accounts.google.com"

echo "==> Verifying signature on $TARGET_IMAGE"
echo "    expected signer: $SIGSTORE_IDENTITY"
echo "    expected issuer: $SIGSTORE_ISSUER"
echo

cosign verify \
    --certificate-identity      "$SIGSTORE_IDENTITY" \
    --certificate-oidc-issuer   "$SIGSTORE_ISSUER" \
    "$TARGET_IMAGE" \
    > /tmp/cosign-verify.json

# Pretty-print the bits that matter
jq '.[0] | {
    image:     .critical.image."docker-manifest-digest",
    signer:    .optional.Subject,
    issuer:    .optional.Issuer,
    bundle_in_rekor: (.optional.Bundle.Payload.logIndex // "unknown")
}' /tmp/cosign-verify.json

cat <<'EOF'

==> Verification OK.
    This image was signed by the Sigstore project's release pipeline.
    The signature is recorded in the public Rekor transparency log.
    No long-lived private keys were involved.

    Try changing TARGET_IMAGE or SIGSTORE_IDENTITY at the top of this
    script and re-running. Any mismatch fails verification — that is
    the whole point.
EOF

rm -f /tmp/cosign-verify.json
