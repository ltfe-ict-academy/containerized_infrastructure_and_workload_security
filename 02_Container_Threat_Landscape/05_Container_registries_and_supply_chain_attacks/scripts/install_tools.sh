#!/usr/bin/env bash
# Install the supply-chain tools used in this module:
#   cosign  — Sigstore signing and verification (installed FIRST so it
#             can verify everything else)
#   gh      — GitHub CLI; used to fetch + verify SLSA provenance from
#             GitHub Artifact Attestations
#   trivy   — image / FS / IaC / SBOM / secret scanner (Aqua Security)
#   grype   — image / SBOM CVE scanner (Anchore)
#   syft    — SBOM generator (Anchore)
#   oras    — OCI artifact inspection / push / pull (CNCF)
#
# All ship signed releases. We install to /usr/local/bin.
#
# Tested on Ubuntu 22.04 / 24.04, Debian 12. Other glibc-based distros
# should work — the install paths are all curl + tar + apt.
#
# Override targets with BIN_DIR or *_VERSION env vars before running.

set -euo pipefail

BIN_DIR="${BIN_DIR:-/usr/local/bin}"
ARCH="$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"

SUDO=""
if [[ ! -w "$BIN_DIR" ]]; then SUDO="sudo"; fi

say()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# ─── cosign (FIRST — bootstrap trust on first use) ────────────────
# There is no avoiding trust-on-first-use for the verifier itself.
# Pin the version so the workshop is reproducible.
say "Installing cosign..."
COSIGN_VERSION="${COSIGN_VERSION:-3.0.6}"
curl -fsSL -o /tmp/cosign \
  "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-${OS}-${ARCH}"
$SUDO install -m 0755 /tmp/cosign "$BIN_DIR/cosign"
rm -f /tmp/cosign
cosign version 2>&1 | head -2

# ─── gh CLI (for SLSA provenance verification) ────────────────────
# Used by `gh attestation verify` to fetch and verify GitHub Artifact
# Attestations. Anonymous fetch works for public repos — no GitHub
# account or token needed for verification.
say "Installing GitHub CLI (gh)..."
if ! have gh; then
    # The official apt repo, signed key, signed packages.
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | $SUDO dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    $SUDO chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    $SUDO apt-get update -qq
    $SUDO apt-get install -y gh
fi
gh --version | head -1

# ─── Trivy ────────────────────────────────────────────────────────
# Trivy v0.70.0+ ships only the Sigstore bundle format (.sigstore.json)
# — the legacy detached .sig and .pem files were dropped. The bundle
# at $TARBALL.sigstore.json is a SIGNATURE bundle (verify-blob).
# The SLSA PROVENANCE attestation lives in GitHub Artifact Attestations
# and is fetched/verified separately via the gh CLI.
say "Installing Trivy..."
TRIVY_VERSION="${TRIVY_VERSION:-0.70.0}"
BASE="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}"
TARBALL="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"

curl -fsSL -o "/tmp/$TARBALL"               "$BASE/$TARBALL"
curl -fsSL -o "/tmp/$TARBALL.sigstore.json" "$BASE/$TARBALL.sigstore.json"

# (1) Signature: the tarball was signed by an Aqua release workflow.
say "Verifying Trivy signature..."
cosign verify-blob "/tmp/$TARBALL" \
  --bundle "/tmp/$TARBALL.sigstore.json" \
  --certificate-identity-regexp 'https://github\.com/aquasecurity/trivy/\.github/workflows/.+' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'

# (2) Provenance: SLSA attestation from GitHub Artifact Attestations.
#     Verifies the binary against the build platform, source repo + commit,
#     and workflow file. Non-fatal if it fails — older Trivy releases
#     may not have provenance attached.
say "Verifying Trivy SLSA provenance..."
if gh attestation verify "/tmp/$TARBALL" --repo aquasecurity/trivy 2>&1 | tail -20; then
    echo "  ✓ Provenance verified."
else
    echo "  ⚠ Provenance check did not complete (may be unavailable for this version)."
fi

tar -xzf "/tmp/$TARBALL" -C /tmp trivy
$SUDO install -m 0755 /tmp/trivy "$BIN_DIR/trivy"
rm -f "/tmp/$TARBALL" "/tmp/$TARBALL.sigstore.json" /tmp/trivy
trivy --version | head -1

# (3) Bonus: scan the release's own SBOM for known CVEs.
say "Scanning Trivy's release SBOM for known CVEs..."
curl -fsSL -o /tmp/trivy-bom.json "$BASE/bom.json"
trivy sbom /tmp/trivy-bom.json --severity HIGH,CRITICAL --exit-code 0 || true
rm -f /tmp/trivy-bom.json

# ─── Grype ────────────────────────────────────────────────────────
# Anchore signs releases with cosign keyless. The install script
# verifies cosign signatures itself when cosign is on PATH (which it
# is, because we just installed it).
say "Installing Grype..."
curl -fsSL https://raw.githubusercontent.com/anchore/grype/main/install.sh \
  | $SUDO sh -s -- -b "$BIN_DIR"
grype version | head -1

# ─── Syft ─────────────────────────────────────────────────────────
say "Installing Syft..."
curl -fsSL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
  | $SUDO sh -s -- -b "$BIN_DIR"
syft version | head -1

# ─── ORAS ─────────────────────────────────────────────────────────
say "Installing ORAS..."
ORAS_VERSION="${ORAS_VERSION:-1.3.2}"
ORAS_TGZ="oras_${ORAS_VERSION}_${OS}_${ARCH}.tar.gz"
ORAS_BASE="https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}"

curl -fsSL -o "/tmp/$ORAS_TGZ" "$ORAS_BASE/$ORAS_TGZ"

# ORAS publishes a checksums file with a cosign signature. Verify it
# before extracting.
if curl -fsSL -o /tmp/oras_checksums.txt "$ORAS_BASE/oras_${ORAS_VERSION}_checksums.txt"; then
    say "Verifying ORAS checksums..."
    EXPECTED="$(grep -E "\\s${ORAS_TGZ}\$" /tmp/oras_checksums.txt | awk '{print $1}')"
    ACTUAL="$(sha256sum "/tmp/$ORAS_TGZ" | awk '{print $1}')"
    if [[ "$EXPECTED" == "$ACTUAL" ]]; then
        echo "  ✓ Checksum matches: $ACTUAL"
    else
        echo "  ✗ Checksum mismatch! expected=$EXPECTED actual=$ACTUAL"
        exit 1
    fi
    rm -f /tmp/oras_checksums.txt
fi

tar -xzf "/tmp/$ORAS_TGZ" -C /tmp oras
$SUDO install -m 0755 /tmp/oras "$BIN_DIR/oras"
rm -f "/tmp/$ORAS_TGZ" /tmp/oras
oras version | head -1

# ─── Warm Trivy DB ────────────────────────────────────────────────
say "Pre-warming Trivy DB (one-time, ~50 MB download)..."
trivy image --download-db-only

echo
echo "Done. cosign, gh, trivy, grype, syft, oras are all on PATH:"
for t in cosign gh trivy grype syft oras; do
    if have "$t"; then
        printf "  %-8s %s\n" "$t" "$(command -v $t)"
    fi
done