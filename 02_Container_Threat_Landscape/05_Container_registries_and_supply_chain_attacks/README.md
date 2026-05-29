# Container Registries and Supply Chain Attacks

This module is the bridge between image hardening and the afternoon's exploitation. A perfectly hardened image is no use if the registry serving it can be tricked into handing your CI an image you did not author. Most attendees come into this module thinking of a registry as "the thing you `docker push` to." By the end of it they should think of a registry as a piece of **trust infrastructure** — and treat it accordingly.

This hour is structured as a short framing block, a taxonomy of supply-chain risks, six hands-on labs, and a discussion of four real attacks that happened in the last 24 months.

## The Last 24 Months in Headlines

You did not need to read security press to see most of these. They were on the front page.

- **March 2024 — XZ / `liblzma` backdoor (CVE-2024-3094).** A two-year social-engineering campaign against an upstream maintainer planted a remote-root backdoor reachable through `sshd` on Debian/Fedora-style distros. Caught by chance, before it shipped to stable, by an engineer noticing the SSH handshake was 500 ms slower than usual.
- **March 2025 — `tj-actions/changed-files`.** A widely used GitHub Action (~20,000 dependent repos) had its `v35` tag rewritten to a malicious commit after the maintainer was phished. Every CI workflow pinned to the tag pulled the attacker's code and exfiltrated secrets.
- **September 2025 — Shai-Hulud npm worm (the original).** The "qix" maintainer was phished via a fake `npmjs.help` domain; 18 packages including `chalk`, `debug`, `ansi-styles`, `strip-ansi` were trojanised (~2.6 billion weekly downloads combined). The payload was a self-propagating worm: it harvested credentials from the victim and used the stolen tokens to publish further packages, multiplying outward. ~500 packages compromised across the first wave.
- **March 2026 — Trivy / Aqua Security supply chain compromise (CVE-2026-33634, GHSA-69fq-xp46-6x23).** Threat actor "TeamPCP" used credentials stolen from an earlier (1 March) Aqua breach that was incompletely remediated. They force-pushed 76 of 77 version tags in `aquasecurity/trivy-action`, replaced all 7 tags in `setup-trivy`, and published malicious Trivy `v0.69.4`, then `v0.69.5` and `v0.69.6` on Docker Hub. The scanner that thousands of pipelines used to check _other_ images was itself the delivery vehicle. The Docker Hardened Images variant of Trivy was unaffected.
- **November 2025 → May 2026 — Shai-Hulud, the sequels.** A drumbeat of follow-on waves, all from the same family of self-replicating malware:
  - **Nov 24, 2025 — Shai-Hulud 2.0 ("Second Coming").** Hundreds of packages from Zapier, ENS Domains, PostHog, Postman, AsyncAPI, Browserbase trojanised. ~700 packages, ~132 M monthly downloads combined. Payload moved to **pre-install** (runs before any security check); secrets exfiltrated to ~27,000 public GitHub repos with the description "Sha1-Hulud: The Second Coming."
  - **Apr–May 2026 — Mini Shai-Hulud.** Hit npm and PyPI simultaneously (TanStack, Mistral AI, UiPath, OpenSearch on 29 April + 11 May). New destructive capability: wipe the victim's home directory if propagation fails.
  - **May 19, 2026 — AntV wave.** TeamPCP (yes, the Trivy group) compromised the `atool` npm maintainer account and published 637 malicious versions across 314 packages in a 22-minute automated burst (~16 M weekly downloads).

That is six headline-grade supply-chain compromises in 26 months, with the same handful of attack patterns recurring: maintainer phishing, mutable tag/version force-push, incomplete credential rotation, and pre-install hooks abused as code-execution gates. In nearly every one, the defence that would have caught the attack was an existing, well-documented best practice — just not one anyone had bothered to apply.

> **The single idea to take home:** a tag is a moving label. A digest is what the runtime will refuse to swap. Sign what you build, verify what you deploy, and keep an SBOM of everything that runs. If your `docker pull` happily accepted whatever was at `nginx:latest` this morning, you don't know what is in production tonight.

Everything else in this module is a consequence of that paragraph.

## Learning Goals

By the end of this hands-on, you should be able to:

- explain the four pillars: image, SBOM, signature, provenance — and why no single one is enough
- distinguish a **tag** from a **digest**, and an **immutable release tag** from a **mutable channel tag**
- run a local registry and demonstrate that the same tag can point to two different images
- pin a deployment to a specific digest so a tag-swap attack cannot succeed
- scan an image for CVEs with **Trivy** and **Grype**, output **SARIF**, and explain why two scanners disagree
- generate an **SBOM** with **Syft** in **SPDX** and **CycloneDX**, and explain what it does and does not prove
- verify a Sigstore signature on a public image with **cosign**, and sign a local image with a keypair for a private registry
- deploy and configure **Harbor** as a production-grade registry with immutability, RBAC, signing enforcement, and replication
- explain the **dependency cooldown** principle and why "patch immediately" is half the answer
- name four major supply-chain incidents of 2024–2026 and what defence would have blocked each

## Prerequisites — Standalone Setup

This module assumes only:

- A Linux host or VM with `sudo` access (Ubuntu 24.04 or similar). Docker Desktop on macOS/Windows also works for the lab portions.
- **Docker Engine + Docker Compose plugin + Docker Post Install as User** installed.
- `curl`, `jq`, `git` available. Install if missing: `sudo apt-get install -y curl jq git`.
- **~5 GB free disk** for the local registry, Harbor, tools, and image cache.
- **Outbound internet access** for Lab 5's public-signature verification and for installing tools. Air-gapped variants are noted where relevant.

You do **not** need anything from earlier modules to run this one — every lab is self-contained.

## Tools You Will Install

We use one tool per job, all free, all actively maintained, all single static binaries with no daemons.

| Tool       | Job                                      | Origin             |
| ---------- | ---------------------------------------- | ------------------ |
| **Trivy**  | image / FS / IaC / SBOM / secret scanner | Aqua Security      |
| **Grype**  | image and SBOM CVE scanner               | Anchore            |
| **Syft**   | SBOM generator (SPDX, CycloneDX, Syft)   | Anchore            |
| **cosign** | container signing & verification         | Sigstore / OpenSSF |
| **ORAS**   | OCI artifact inspection / push / pull    | CNCF               |
| Harbor     | enterprise OCI registry (separate lab)   | CNCF               |

One-shot installer for all the CLI binaries:

```bash
./scripts/install_tools.sh
```

> **Pin the scanner — and verify what you pinned.** After the Trivy 2026 incident, "pin and verify your scanner image to a digest" is no longer optional. The same applies to the binary you download to install in the first place. We do exactly that in Lab 3, and the install script does the same — see the verification step below.

> Look at the `install_tools.sh` code and check how it verifies the Trivy itself.

Moving from: All we check is that the bytes arrived from `github.com` over TLS. We have no idea who put them there or whether they were tampered with after upload. If GitHub had a bad day, or our DNS was hijacked, we'd happily install whatever showed up.

Towards: The Trivy GitHub release page ships **four extra files per artifact** so you can do better:

| File                                                                     | Purpose                                                                                         |
| ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| `…tar.gz.sig`                                                            | Detached cosign signature (legacy format).                                                      |
| `…tar.gz.pem`                                                            | Signing certificate (Fulcio-issued, short-lived, embeds the OIDC identity that signed).         |
| `…tar.gz.sigstore.json`                                                  | Newer Sigstore "bundle": signature + cert + Rekor entry + in-toto attestation, all in one file. |
| `trivy_<ver>_checksums.txt` (and an SBOM `bom.json` shipped per release) | SHA-256 checksums and a CycloneDX SBOM of the released binary.                                  |

## The Mental Model — Four Pillars

Every meaningful statement about a container image hangs off four artifacts.

| Pillar         | Tells you…                 | Produced by           | Format              | Checked by                                                                 |
| -------------- | -------------------------- | --------------------- | ------------------- | -------------------------------------------------------------------------- |
| **Image**      | "this is the running code" | the build             | OCI image manifest  | digest comparison (`docker pull` enforces it; `crane`/`skopeo` inspect it) |
| **SBOM**       | _what is in_ the image     | build or scanner      | SPDX / CycloneDX    | `grype sbom:…`, `trivy sbom …`, Dependency-Track, DefectDojo               |
| **Signature**  | _who_ put the image there  | signing identity (CI) | Sigstore / Notation | `cosign verify` (image), `cosign verify-blob` (file), `notation verify`    |
| **Provenance** | _how_ the image was built  | build platform        | SLSA / in-toto      | `cosign verify-attestation`, `slsa-verifier`, `gh attestation verify`      |

You need **all four** for meaningful supply-chain integrity. The image alone is just bytes. The SBOM without a signature is just a list anyone could forge. The signature without a provenance attestation only proves "someone we trust ran a build," not "they built it from the source we expect." This is the framework you will hear repeated under various names — **SLSA**, **SSDF**, **EO 14028**, **EU CRA** — they are all asking for the same four artifacts plus a way to verify them.

Module 2.3 (The Image Problem) covered _what is inside_ an image. This module covers _how it got to production_ and _how you prove that_.

## Tags, Digests, and Why Both Tag Kinds Are Lies

A **tag** is a human-readable pointer (`nginx:latest`, `redis:7.2.4`). A **digest** is a SHA-256 hash of the image's manifest — `sha256:abc123…`. The digest **identifies** the image. The tag is a name someone chose to apply to it, and that someone can change their mind. Therefore, the digest identifies the image manifest, and the manifest cryptographically identifies the exact config and layer blobs that make up the image - cryptographic chain.

> List with: `docker manifest inspect nginx:latest | jq .` or with: `docker buildx imagetools inspect nginx:latest --raw | jq .`. Inspect the top-level digest with: `docker buildx imagetools inspect \
  nginx@sha256:0a0b02fec34ea28aac0f7e0cf8403e5c9ee5fc201162eae5bf891a84e5599281 \
  --raw | jq .`.

Two important sub-categories of tags:

- **Immutable release tags** look like real versions: `redis:7.2.4`, `nginx:1.27.3-alpine`, `myapp:v1.0.0-rc5`. By **convention** these are bound to a single release and never moved. But this is only convention — nothing in Docker, the OCI spec, or any registry's default config stops the publisher from re-pushing a different image under the same tag. Some registries (Harbor, AWS ECR, Google Artifact Registry, GHCR) let you turn on **tag immutability** as a policy, which makes the registry refuse the overwrite. Docker Hub does _not_ offer this for free-tier repos. The tj-actions and Trivy 2026 incidents both worked by force-pushing what looked like immutable version tags.
- **Mutable channel tags** are pointers by design: `:latest`, `:stable`, `:edge`, `:dev`, `:7` (the "newest 7.x"), `:lts`. These are _supposed_ to move. They are convenient for development and disastrous for production, because their whole purpose is silent drift.

The rule: **even when a tag looks immutable, it isn't unless the registry enforces it.** Pin to digests in production, period.

## Standards You Will Hear About

A glossary, because the room will throw acronyms at you all week.

- **OCI** — Open Container Initiative. Three specs: image-spec (the manifest + layers format), distribution-spec (the HTTP API every registry implements), and runtime-spec (how to actually execute the bundle). When you `docker pull`, you are speaking distribution-spec to the registry and image-spec to the layers it returns.
- **OCI artifacts** — the same image-spec also stores things that are _not_ images: SBOMs, signatures, attestations, Helm charts. ORAS is the tool for pushing/pulling them. When `cosign sign` runs, the signature lands in the registry as an OCI artifact tagged `sha256-<digest>.sig` next to the image it covers.
- **SPDX** — Software Package Data Exchange. SBOM format. ISO/IEC 5962, originated at the Linux Foundation, version 2.3 / 3.0 current. Verbose, well established.
- **CycloneDX** — OWASP's SBOM format. Slightly newer, more compact, has richer support for vulnerability/VEX attestation alongside the bill of materials. Either format is fine; pick one organisationally and stick with it.
- **SARIF** — Static Analysis Results Interchange Format (OASIS standard). A JSON format for scanner output that GitHub, GitLab, and most security platforms consume directly. Trivy, Grype, and most scanners can emit SARIF — that is what you want for "show this finding in my PR review" workflows.
- **VEX** — Vulnerability Exploitability eXchange. A signed statement that says, for a given CVE in a given artifact: _affected_ / _not_affected_ / _fixed_ / _under_investigation_. A scanner that finds CVE-X in your image, plus a vendor VEX that says "_not_affected_ because the vulnerable code path isn't reachable," is how you stop drowning in false positives.
- **in-toto** — a framework (CNCF) for attesting "each step in the supply chain ran in the right order, with the right inputs, by the right party." Provenance documents are usually in-toto statements.
- **SLSA** — Supply chain Levels for Software Artifacts (pronounced "salsa"). OpenSSF framework. The **Build track** currently defines four discrete tiers:

  | Level  | What's required                                                                                                                           |
  | ------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
  | **L0** | No provenance. Default for "I built this on my laptop."                                                                                   |
  | **L1** | The build platform generates provenance describing how the artifact was built; provenance is available to consumers (it may be unsigned). |
  | **L2** | Builds run on a hosted platform that **signs** the provenance itself (so a leaked tenant credential cannot mint fake provenance).         |
  | **L3** | Hardened, isolated build platform: runs cannot influence each other, signing material is inaccessible to user-defined build steps.        |

  Most organisations should aim for **L2-L3**. GitHub-hosted runners with `slsa-framework/slsa-github-generator` produce L3-eligible signed provenance. (A "Source track" exists with its own levels; that's orthogonal to the build levels above.)

- **CIS Docker Benchmark** — the de-facto compliance checklist for Docker hosts and Docker daemons. `docker-bench-security` runs the checks. Not registry-specific, but most enterprise registry deployments map their hardening to CIS controls. We'll touch this again in Module 4.
- **Notation v2** (formerly Notary) — Microsoft/AWS-backed alternative to Sigstore. Same goal (signed OCI artifacts), different cryptography (long-lived keys, X.509). If your registry vendor is Microsoft, AWS, or you are in regulated environments that require non-keyless signatures, Notation is the supported path.

## Registries In Production

Not all registries are equal. Quick survey of what you might encounter:

| Registry                             | Tag immutability      | Signing support                                    | Replication / mirror     | Hosted vs self-host |
| ------------------------------------ | --------------------- | -------------------------------------------------- | ------------------------ | ------------------- |
| **Docker Hub**                       | paid plans only       | external (cosign)                                  | Hub mirror feature       | hosted              |
| **GitHub Container Registry (GHCR)** | yes (rules)           | OCI-native (cosign signatures stored as artifacts) | via GitHub Actions       | hosted              |
| **AWS ECR**                          | yes (project setting) | OCI-native; integrates with Signer                 | cross-region replication | hosted              |
| **Google Artifact Registry (GAR)**   | yes (per repo)        | Binary Authorization integrates with cosign        | regional replication     | hosted              |
| **Quay (Red Hat)**                   | yes                   | Notary v1 (deprecated) + cosign                    | geo-replication          | both                |
| **Harbor**                           | yes (per project)     | cosign + notation, built-in                        | replication policies     | self-host only      |
| **JFrog Artifactory**                | yes                   | both                                               | cross-instance           | both                |

For internal/regulated/air-gapped deployments, **Harbor** is the most common open-source choice. It is a full reference implementation: vulnerability scanning hooks, image signing policy enforcement, project-level RBAC, replication, retention, garbage collection. We will deploy one in Lab 6.

## The Supply Chain Risk Taxonomy

Ten failure modes that turn a working registry into an attack surface. Each of the labs maps to one or more of them.

1. **Blind trust in public registries.** "It's on Docker Hub, must be fine." Docker Hub has had cryptominer-laden images (`docker123321`, 2017-18, 17 images, millions of pulls) and unauthorised mirrors of legitimate images. Even "Official Images" can carry CVEs that ship for months before rebuild. Treat _every_ image you didn't build like third-party code: SBOM it, scan it, store it in a private registry with provenance attached.

2. **Overpowered registry credentials.** A CI token that can push to any production repo is a credential that, if leaked, ends the conversation. Most pipelines run with a single robot account that can push to everything; the principle of least privilege says one robot per repo per environment, with push scope restricted by path. Harbor and most modern registries support this; almost nobody configures it.

3. **Compromised CI/CD feeding the registry.** The image is fine. The Dockerfile is fine. But the _step_ that built it ran attacker code, or used a tagged third-party action that got rewritten under your feet. The tj-actions, Trivy, and Shai-Hulud incidents are all this category. CI is part of your supply chain; pin its actions to SHAs, restrict its tokens, and audit its outbound traffic.

4. **No cryptographic verification.** "We trust this image because we trust the registry it came from." Wrong. The registry can be tag-swapped, mirrored maliciously, or compromised. Verification of a Sigstore signature at deploy time is the only thing that gives you cryptographic certainty that the bytes you are running came from the identity you expect.

5. **No provenance.** "Where did this image come from?" If your answer is "the registry," you've described where it was _stored_, not where it was _built_. A SLSA provenance attestation tells you which source commit, which build platform, which workflow, which build parameters — and is signed by the build platform itself. Without this, you cannot do post-incident forensics, you cannot prove regulatory compliance (EO 14028, EU CRA), and you cannot detect the kind of build-time backdoor that hit XZ.

6. **Registry scanning treated as a silver bullet.** "Trivy / Grype / Snyk found no CVEs, so the image is safe." It is safe _against the CVEs they know about today_. It is not safe against the next CVE (no scanner predicts the future), against insecure defaults, against credentials baked into a layer, or against malicious packages that the public DB hasn't caught yet. Scanning is necessary; it is the floor, not the ceiling.

7. **Registry access rules too open.** Many internal Harbor/Quay deployments default to "authenticated users can pull anything." This is the same anti-pattern as a flat internal network. Sensitive images (production builds, anything containing internal addresses, certificates, customer-data fixtures) belong in projects that are restricted by role. Pull events should be logged and alerted on for sensitive projects.

8. **Pull-through mirrors and cached content that nobody monitors.** A registry mirror or proxy cache (`registry-mirrors` in `daemon.json`, Harbor pull-through projects, JFrog remote repos) caches upstream images locally. The cache means yesterday's `nginx:1.27` and today's `nginx:1.27` could resolve to different bytes for different hosts on your network. Nobody alerts when the upstream digest changes. Old caches with vulnerable versions of images keep serving even after the upstream has been patched.

9. **Registry availability and operational risk.** Your registry is now in your critical path for deployments, rollbacks, autoscaling, and disaster recovery. If your only copy of a production image is on Docker Hub and Docker Hub is having a bad day, your incident is now Docker Hub's incident. Mirror your dependencies. Run a fallback registry in another region. Have a documented recovery procedure for the case of "the registry is down and we need to redeploy now."

10. **Stale `:latest` and the absence of cooldown.** Two opposite mistakes. Many production deployments never update their base images, accumulating CVEs for years. Many others auto-update on every `:latest` push, accepting whatever the upstream has pushed in the last hour — which is when supply-chain compromises bite. The right answer is a **cooldown** (Lab 7).

---

# Hands-on Labs

## Lab 1 — A Tag Is a Lie

We run a local registry, push two different images to the same tag, and watch a `docker pull` happily accept the swap.

### Step 1: Start a local registry

```bash
cd local_registry
docker compose up -d
docker compose ps
```

You now have an OCI distribution server on `localhost:5000`. This is the reference `registry:2` image that backs Docker Hub, Quay, GHCR, GitLab Container Registry, Harbor, and Artifactory — they are all forks or wrappers of this single reference implementation.

### Step 2: Push image v1 (the "good" one)

```bash
docker build -t localhost:5000/internal/payments:prod ./v1
docker push localhost:5000/internal/payments:prod
```

Save the digest:

```bash
GOOD_DIGEST=$(docker inspect --format '{{index .RepoDigests 0}}' \
    localhost:5000/internal/payments:prod | cut -d@ -f2)
echo "GOOD: $GOOD_DIGEST"
# GOOD: sha256:4a2c...   (yours will differ)

docker run --rm localhost:5000/internal/payments:prod
# payments service starting...
```

### Step 3: Push image v2 (the "bad" one) — same tag, different bytes

```bash
docker build -t localhost:5000/internal/payments:prod ./v2
docker push localhost:5000/internal/payments:prod

BAD_DIGEST=$(docker inspect --format '{{index .RepoDigests 0}}' \
    localhost:5000/internal/payments:prod | cut -d@ -f2)
echo "BAD: $BAD_DIGEST"
# BAD: sha256:91fe...   (different!)
```

We have just performed a **tag-swap attack** against ourselves.

> Note: You can use Registry HTTP API to list the registry catalog using `curl http://127.0.0.1:5000/v2/_catalog` or `curl http://127.0.0.1:5000/v2/internal/payments/tags/list` to list specific tags.

> Note: There is no nice "history" API to show tag history/swaps! This is why you get storage garbage in part if `REGISTRY_STORAGE_DELETE_ENABLED` is `disabled` and you don't delete old digests (only in part due to layer reuse). Production registries do this better (immutable tags, audit logs, ui for digests, project cleanup rules, ...).

### Step 4: Confirm the swap

```bash
docker rmi localhost:5000/internal/payments:prod
docker pull localhost:5000/internal/payments:prod
docker run --rm localhost:5000/internal/payments:prod
# payments service starting...
# [backdoor] hello from the malicious version
```

The two images are _indistinguishable by tag_. Anyone in the org who does a fresh pull from this moment forward gets the v2 image. This is exactly how the tj-actions 2025 incident worked — except the tag in question was `v35` in `git`, not `:prod` in a registry, and the bytes were attacker malware, not a hello banner.

> **Why this matters in real life:** Many registries (Harbor, ECR, GAR, GHCR) support **tag immutability** as a per-project or per-repo setting. The default everywhere is "off." Turn it on for everything that goes to production.

---

## Lab 2 — The Fix Is a Digest

A digest is a content hash. `sha256:91fe...` _is_ the image. You cannot have two different images with the same digest; the second would require a SHA-256 collision, which we will worry about in a few thousand years.

### Step 1: Try to deploy by tag — get hit by the swap

```bash
docker compose -f deploy/compose-tag.yaml up -d
docker compose -f deploy/compose-tag.yaml logs
# payments | [backdoor] hello from the malicious version
docker compose -f deploy/compose-tag.yaml down
```

### Step 2: Pin to the _good_ digest

Edit `deploy/compose-digest.yaml`:

```yaml
services:
  payments:
    image: localhost:5000/internal/payments@sha256:4a2c... # your $GOOD_DIGEST
```

```bash
docker compose -f deploy/compose-digest.yaml up -d
docker compose -f deploy/compose-digest.yaml logs
# payments | payments service starting...    <- back to the good one
```

### Step 3: Confirm the registry now physically cannot swap it

```bash
docker build -t localhost:5000/internal/payments:prod ./v2
docker push localhost:5000/internal/payments:prod
docker compose -f deploy/compose-digest.yaml up -d --force-recreate
docker compose -f deploy/compose-digest.yaml logs
# payments | payments service starting...    <- still good
```

The compose stack is pinned to the digest of the v1 image. The tag can be swapped a thousand times; Docker will still pull the bytes that hash to `sha256:4a2c...`. If the registry serves anything else under that name, the pull fails with `manifest digest mismatch`.

**This is the single highest-value thing in this entire module.** Digest-pin every production image. Tools like **Renovate**, **Dependabot**, **Argo CD**, and **Flux** can resolve `tag → digest` at deploy time and write the digest into the manifest automatically (while keeping audit history or requesting change approval).

---

## Lab 3 — Scanning: Two Tools, Two Answers, One SARIF

We scan the same image with two of the most popular scanners and observe that they disagree. Then we discuss why, and emit results in **SARIF** for CI integration.

### Step 1: Pull a deliberately old image

```bash
docker pull node:14.17.0
```

### Step 2: Scan with Trivy

A direct command (this is what the helper script wraps):

```bash
trivy image --severity HIGH,CRITICAL --ignore-unfixed node:14.17.0
```

Or with the helper:

```bash
./scripts/scan_trivy.sh node:14.17.0
```

Trivy output:

```text
Total: 1247 (UNKNOWN: 0, LOW: 145, MEDIUM: 612, HIGH: 397, CRITICAL: 93)
```

### Step 3: Scan with Grype

```bash
grype node:14.17.0 --only-fixed
# or:  ./scripts/scan_grype.sh node:14.17.0
```

Grype output:

```text
[X CVEs total]   Critical: 105   High: 388   Medium: 590
```

### Step 4: Emit SARIF for CI integration

SARIF is the JSON format GitHub, GitLab, and most security platforms ingest natively. The same scan, emitted as SARIF, lands as inline annotations in PR reviews:

```bash
trivy image --format sarif -o results.sarif node:14.17.0
grype  node:14.17.0 -o sarif > grype-results.sarif

# Quick peek
jq '.runs[0].results | length' results.sarif
# 1247
```

In GitHub Actions, the canonical pattern is `aquasecurity/trivy-action` → `github/codeql-action/upload-sarif`. **Pin both to commit SHAs**, not version tags — see the Trivy and tj-actions cases below.

### Why the disagreement?

Each scanner has its own:

- **Vulnerability database** — Trivy bundles its own; Grype uses Anchore's; both sync from NVD, GHSA, Red Hat OVAL, Alpine secdb, Debian Security Tracker.
- **Package detector** — which package managers, lockfiles, and language manifests they understand.
- **CVE matching logic** — a CVE may say "OpenSSL 1.1.1 < 1.1.1k," but a Linux distro often backports the patch into an older version number; different scanners read the distro security advisories differently.
- **False-positive heuristics** — does the scanner know that this CVE is only exploitable in a specific build flag combination?

You will see this disagreement at every customer site. The right reaction:

1. Pick one tool as your gate. Either Trivy or Grype is fine.
2. Run a second tool as a check, not as a gate. The disagreement is information.
3. Triage on **fixable, exploitable, internet-reachable** CVEs first, not on "CRITICAL count."
4. Use **VEX** when available to filter false positives.
5. Track image age — most CVEs are fixed by rebasing on a newer minor of your base image, not by patching individual packages.

> Note: Use VEX filtering like this:
>
> ```bash
> trivy image --vex oci node:14.17.0
> # or
> trivy image --vex repo node:14.17.0
> ```
>
> (Keep in mind VEX might not be available for your image)
> (It is for Trivy itself: `trivy image ghcr.io/aquasecurity/trivy:0.52.0 --vex repo`)
>
> Compare:
> `trivy image ghcr.io/aquasecurity/trivy:0.52.0 --format sarif | jq '.runs[0].results | length'`
> `trivy image ghcr.io/aquasecurity/trivy:0.52.0 --vex repo --format sarif | jq '.runs[0].results | length'`

### Step 5: A modern image

```bash
docker pull node:22-alpine
trivy image --severity HIGH,CRITICAL --ignore-unfixed node:22-alpine
```

The numbers will be radically lower — sometimes zero criticals. The single biggest CVE reduction in containers is "rebase on a current base image."

> **Misconception:** "Trivy / Grype / Snyk found no CVEs, so the image is safe." It is safe _against the CVEs they know about_. It is not safe against the next CVE, against insecure defaults, against credentials baked into a layer, or against a malicious package the public DB hasn't caught yet. The Trivy March 2026 incident is a case in point — see below.

### Step 6 — Pin and verify your scanner image

The scanner is in your supply chain. After Trivy 2026, this is no longer optional. In your CI:

```yaml
# GOOD — pinned to digest and to SHA
- uses: aquasecurity/trivy-action@<commit-sha>
  with:
    image-ref: ghcr.io/myorg/myapp@sha256:abc... # not :latest
# BAD — anything that uses a mutable tag
- uses: aquasecurity/trivy-action@master # tj-actions repeat business
```

### Optional — pipe scans into DefectDojo

For a long-term view, scan results are most useful when they land in a vulnerability management system, not in CI logs. **DefectDojo** (open source, Python/Django, OWASP) ingests SARIF, Trivy JSON, Grype JSON, and ~150 other tool outputs, tracks findings across builds, supports SLAs, and de-dupes. Most security teams don't know it exists, and it removes the "CSV in someone's email" pattern that most orgs default to.

DefectDojo is multi-service (django + nginx + postgres + valkey + celery beat + celery worker + an initializer). The official compose file the right entry point. Loopback-only setup:

```bash
cd /tmp
git clone --depth 1 https://github.com/DefectDojo/django-DefectDojo dojo
cd dojo

# Bind every published port to 127.0.0.1 only, so the workshop install isn't
# accidentally on the LAN. Same trick we used for Harbor.
python3 - <<'PY'
import re
with open('docker-compose.yml') as f:
    text = f.read()
def rewrite(line):
    m = re.match(r'(\s*-\s*)"?(\d+):(\d+)(/\w+)?"?\s*$', line)
    if not m: return line
    indent, host, ctr, proto = m.groups()
    proto = proto or ""
    return f'{indent}"127.0.0.1:{host}:{ctr}{proto}"\n'
out, in_ports, ports_indent = [], False, None
for line in text.splitlines(keepends=True):
    s = line.rstrip("\n")
    if re.match(r'^\s*ports:\s*$', s):
        in_ports = True; ports_indent = len(s) - len(s.lstrip()); out.append(line); continue
    if in_ports:
        if line.strip() == "": out.append(line); continue
        if len(line) - len(line.lstrip()) <= ports_indent:
            in_ports = False; out.append(line); continue
        out.append(rewrite(line))
    else: out.append(line)
with open('docker-compose.yml','w') as f: f.writelines(out)
PY

docker compose up -d

# Wait for the initializer to finish (up to ~3 minutes) and grab the admin password
docker compose logs -f initializer | grep -m1 "Admin password:"
```

The UI is now on `127.0.0.1:8080` on the VM. From your laptop:

```bash
ssh -L 8080:127.0.0.1:8080 <user>@<vm>
# then open http://127.0.0.1:8080 in your laptop browser
```

Log in as `admin` with the password the initializer printed. Engagements → Import Scan Results → upload `results.sarif` or any Trivy/Grype JSON.

Teardown:

```bash
cd /tmp/dojo && docker compose down -v && cd .. && rm -rf dojo
```

---

## Lab 4 — Generate an SBOM with Syft

An **SBOM** is a manifest of every package the image contains. It does not on its own prove anything is safe — but every tool downstream of it (signing, attestation, CVE lookup, policy, license audit) needs one.

```bash
mkdir -p sboms/node-22-alpine

# Three formats from one tool
syft node:22-alpine -o spdx-json      > sboms/node-22-alpine/spdx.json
syft node:22-alpine -o cyclonedx-json > sboms/node-22-alpine/cyclonedx.json
syft node:22-alpine -o syft-json      > sboms/node-22-alpine/syft.json

# Or with the helper:
./scripts/sbom_syft.sh node:22-alpine sboms/node-22-alpine

ls sboms/node-22-alpine
head -20 sboms/node-22-alpine/spdx.json
```

**SPDX** vs **CycloneDX**:

- **SPDX** is older, ISO/IEC 5962 standard, originated at the Linux Foundation. Verbose JSON, very explicit relationships between packages, strong license model.
- **CycloneDX** is OWASP's, slightly newer and more compact, native VEX support, stronger story for vulnerabilities and signature attestation alongside the inventory.

Either is fine. Pick one organisationally. Most modern tools accept either. The big consumers (DefectDojo, Dependency-Track, Grype) are format-agnostic.

You can scan an SBOM directly, without re-inspecting the image:

```bash
grype sbom:sboms/node-22-alpine/syft.json
```

This is the workflow most production CI pipelines use: **build → SBOM → scan SBOM → sign image + SBOM → push**. Scanning the SBOM is faster and more deterministic than scanning the image; it's also what lets you re-scan yesterday's images against today's CVE database without rebuilding.

> An SBOM tells you what is in the image. It does not tell you what was used to build it (that is **provenance**), and it does not tell you that the image is what you think it is (that is **signing**). Treat it as one of four artifacts: image, SBOM, signature, provenance.

> Note: You can scan also the SBOM like so: `trivy sbom sbom.cdx.json`

---

## Lab 5 — Sigstore: Cryptographic Trust for Images

Tags are a label. Digests are bytes. **Signatures** are someone telling you the bytes are theirs.

### What Sigstore actually is

Three things plumbed together:

1. **Fulcio** — a public Certificate Authority that issues _short-lived_ (10-minute) X.509 certificates bound to an OIDC identity. You authenticate as `alice@example.com` (or as a GitHub Actions workflow URL like `https://github.com/your-org/your-repo/.github/workflows/release.yaml@refs/heads/main`), and Fulcio gives you a cert that says "the holder of this private key is, right now, that identity."
2. **Rekor** — a public, append-only Merkle-tree transparency log. Every signature ever made with Fulcio gets a Rekor entry. Anyone, ever, can later ask "was this signature made? when? by whom?"
3. **cosign** — the CLI. You run `cosign sign $IMAGE@sha256:...` and it:
   - generates an ephemeral key pair in memory
   - opens a browser (or uses your CI's OIDC token) to authenticate you
   - asks Fulcio for a cert
   - signs the image digest
   - uploads the signature + cert to the registry as an OCI artifact tagged `sha256-<digest>.sig`
   - logs the signature to Rekor
   - throws the private key away

No long-lived signing keys, nothing to rotate, nothing to revoke. If your CI is compromised tomorrow, an attacker can sign things _from tomorrow forward as your CI_ — but they cannot retroactively forge signatures, and your verifier can simply refuse signatures dated after the compromise.

### Public-registry verification (keyless)

The cleanest verification example is the cosign binary itself. The project signs every release.

```bash
cd signing
./verify_public.sh
```

That script runs:

```bash
cosign verify \
    --certificate-identity    'keyless@projectsigstore.iam.gserviceaccount.com' \
    --certificate-oidc-issuer 'https://accounts.google.com' \
    ghcr.io/sigstore/cosign/cosign:v2.4.1
```

What the two flags actually mean:

- **`--certificate-oidc-issuer`** is the URL of the **OIDC identity provider** that issued the token to the signer. Common issuers you'll see in the wild:

  | Signer is...                                | OIDC issuer URL                                       |
  | ------------------------------------------- | ----------------------------------------------------- |
  | A GitHub Actions workflow                   | `https://token.actions.githubusercontent.com`         |
  | A GitLab CI job                             | `https://gitlab.com` (or your self-hosted GitLab URL) |
  | A human signing in with a Google account    | `https://accounts.google.com`                         |
  | A human signing in with Microsoft / Entra   | `https://login.microsoftonline.com/<tenant>/v2.0`     |
  | A GCP service account (Cloud Build, gcloud) | `https://accounts.google.com`                         |

  Cosign fetches the issuer's `/.well-known/openid-configuration` document to validate the certificate chain.

- **`--certificate-identity`** (exact match) or **`--certificate-identity-regexp`** (pattern) is the **subject** claim of the OIDC token — _who_ did the signing:

  | Signer                  | Subject value                                                                     |
  | ----------------------- | --------------------------------------------------------------------------------- |
  | GitHub Actions workflow | `https://github.com/<org>/<repo>/.github/workflows/<file>.yml@refs/heads/main`    |
  | Human via Google OAuth  | the user's email address, e.g. `alice@example.com`                                |
  | GCP service account     | the service-account email, e.g. `keyless@projectsigstore.iam.gserviceaccount.com` |

> **Worth knowing:** many tutorials say the Sigstore project signs `cosign` releases via a GitHub Actions workflow. It doesn't — releases go through Google Cloud Build, so the signer is the GCP service account `keyless@projectsigstore.iam.gserviceaccount.com` and the issuer is `https://accounts.google.com`. If you copy a verification command for the wrong project, you'll get this error:
>
> ```text
> Error: no matching signatures: ... none of the expected identities matched what
> was in the certificate, got subjects [keyless@projectsigstore.iam.gserviceaccount.com]
> with issuer https://accounts.google.com
> ```
>
> The error message tells you exactly what subject and issuer cosign _did_ find on the cert. The fix: if the values you see are the ones you actually expected, plug them into the flags. If they aren't, that **is** the verification working — somebody other than who you expected signed this image, and you should not trust it.

If verification succeeds, cosign prints a JSON document that includes the Rekor log index, the Fulcio cert, and the image digest. If anyone in the middle had swapped the image, the verification fails loudly.

### Private / local-registry signing (keypair)

Keyless signing requires that your build environment reach `fulcio.sigstore.dev` and `rekor.sigstore.dev`, and that you trust the public Sigstore roots. For air-gapped, regulated, or fully internal environments, you have two options:

**Option A — Keypair signing with cosign.**

```bash
# Generate a keypair (you'll be prompted for a passphrase)
cosign generate-key-pair
# → cosign.key (private; protect this!) + cosign.pub (distribute)

# Sign the local registry image from Lab 1
cosign sign --key cosign.key localhost:5000/internal/payments@${GOOD_DIGEST}
# Note: This pushes the signature to your registry!
# Check with:
curl -s http://localhost:5000/v2/internal/payments/tags/list | jq
# or
cosign tree localhost:5000/internal/payments@${GOOD_DIGEST}

# Verify
cosign verify --key cosign.pub localhost:5000/internal/payments@${GOOD_DIGEST}
```

The private key is now your problem. **In production:**

- **Never** store `cosign.key` on disk on a CI runner. Store it in your CI's secret manager (GitHub Actions secrets, GitLab CI/CD variables, Vault) and let cosign read it via env var.
- For real production, use a KMS backend. cosign supports **AWS KMS**, **GCP KMS**, **Azure Key Vault**, **HashiCorp Vault**, and **PIV** (hardware tokens like YubiKey):
  ```bash
  cosign sign --key awskms:///arn:aws:kms:eu-central-1:123:key/abc \
              localhost:5000/internal/payments@${GOOD_DIGEST}
  ```
- Rotate keys periodically and revoke compromised ones by removing the public key from your verification policy.

**Option B — Run your own Sigstore.** The Sigstore stack is open source. You can host your own Fulcio and Rekor inside your perimeter (the project ships Helm charts for this). Your air-gapped CI then signs against the internal instance, with no dependency on the public infrastructure. This is more work but is what regulated environments do.

**Option C — Self-hosted GitLab (or any non-GitHub CI).**

Sigstore is platform-neutral: the only thing that varies between CI providers is the OIDC issuer URL and the certificate identity claim. A GitLab CI job on your own self-hosted instance can sign with keyless OIDC against your own Fulcio + Rekor, push the SLSA provenance attestation alongside the image in your private registry as an OCI artifact, and have any consumer verify it with the same `cosign verify-attestation` command — pointed at your GitLab issuer instead of GitHub's:

​`bash
cosign verify-attestation \
    --certificate-identity-regexp 'https://gitlab.example.com/group/project//.gitlab-ci.yml@refs/.+' \
    --certificate-oidc-issuer 'https://gitlab.example.com' \
    --type slsaprovenance \
    internal-registry.example.com/team/image@sha256:abc...
​`

Compared to the GitHub case, the only changes are the two identity flags. Everything else — the bundle format, the Rekor inclusion proof, the verification command — is identical. For MoD/regulated/air-gapped deployments this is the realistic shape: a self-hosted GitLab Runner pipeline emitting SLSA provenance signed by an internal Sigstore stack, with attestations stored next to images in your private OCI registry, verified at deploy time by Kyverno or sigstore-policy-controller running against the same internal issuer.

The same pattern applies to Buildkite, CircleCI, Jenkins with OIDC, Google Cloud Build, AWS CodeBuild — any CI that can mint an OIDC token, with `cosign` doing the actual signing and Sigstore (internal or public) backing it.

### Where signing belongs in your stack

```text
build → sign → push → store → verify → deploy
          │                       │
          ▼                       ▼
       (cosign)                (policy engine)
```

The signing happens in CI, right after `docker build`. The verification happens in your **policy engine** at deploy time, _before_ the kubelet/Docker pulls the image.

Policy engines (admission webhooks for Kubernetes — covered in Module 4):

- **sigstore-policy-controller** — official Sigstore project, native, supports keyless and key-based.
- **Kyverno** — broader policy engine; has rich `verifyImages` rules.
- **OPA Gatekeeper** — Rego-based; flexible, slightly more glue required.
- **Connaisseur** — older, originally PGP-based, now supports Sigstore.

For plain Docker (no Kubernetes), the closest things are out-of-band CI gates running `cosign verify` before `docker compose up`. **Harbor** has built-in support for cosign signature policies — pulls of unsigned images are refused at the registry level (Lab 6).

### Docker Hardened Images — a Sigstore consumer story

Docker's **Docker Hardened Images** (DHI) tier, launched in late 2024, is a paid product but is worth knowing about because it represents what "a properly-supplied container image" now looks like. Every DHI image ships with:

- **An SBOM** (SPDX) attached as an OCI artifact
- **A Sigstore signature** issued by Docker's CI
- **SLSA L3 provenance** attestation
- **A published vulnerability remediation SLA** — security patches within fixed time windows
- **Continuous rebuilds** — when an upstream CVE drops, the DHI base is rebuilt and re-signed automatically

The Trivy 2026 compromise hit the standard `aquasec/trivy` Docker Hub image. The **Docker Hardened Image version of Trivy was unaffected** — a different image, with a different supply chain, signed and provenanced separately. That is the kind of layered defence you should be aiming for.

Other suppliers play in the same space: **Chainguard Images** (now part of GitLab) ship minimal, signed, SBOM-attached images of common workloads. **Wolfi**-based distro images. **Red Hat's Universal Base Images** (UBI). **Iron Bank** for U.S. federal compliance. The product matters less than the artifact set: SBOM + signature + provenance + a rebuild SLA.

---

## Lab 6 — Harbor: A Production-Grade Registry

`registry:2` is the reference implementation. **Harbor** is the production wrapper around it: RBAC, project isolation, replication, vulnerability scanning, tag immutability policies, retention, garbage collection, signing enforcement, audit logs.

We will deploy Harbor on your VM, push an image to it, and walk through the security-relevant policies.

### Step 1 — Deploy Harbor

Harbor ships an installer that pulls all its components (postgres, redis, registry, core, jobservice, portal, exporter) into a single Compose stack. From `harbor/` in this module:

```bash
cd harbor
sudo ./install_harbor.sh
```

After ~3 minutes you'll have a working Harbor on `http://127.0.0.1:8080`. Log in with `admin` / `Harbor12345`.

### Step 2 — Walk through the security-relevant features

In the Harbor UI:

1. **Projects → New Project → `payments`** (private). This is your isolation unit. Every image lives inside a project. RBAC is per-project: members can have `Limited Guest`, `Guest`, `Developer`, `Maintainer`, `Project Admin`.
2. **Project `payments` → Configuration:**
   - **Deployment security → Cosign**: enable. Now Harbor refuses to serve unsigned images at pull time.
   - **Vulnerability scanning → Prevent vulnerable images from running**: set the severity threshold (`High` or above for `payments`).
3. **Project `payments` → Policy → Tag immutability → New Rule**: pattern `**`. Now nobody — not even Project Admin — can overwrite a tag in this project.
4. **Project `payments` → Policy → Tag retention → New Rule**: e.g., keep last 10 tags matching `v*` — keeps clutter from accumulating but doesn't accidentally delete what's signed and pinned.
5. **System → Robot Accounts → New robot account**: scoped to project `payments`, permissions `Push`, `Pull`. This is the credential your CI gets — not an admin password.

### Step 3 — Push to Harbor with a robot credential

```bash
# Log in with the robot token, NOT with admin
docker login localhost:8080 -u 'robot$payments+ci' -p '<robot-token>'

# Tag and push the v1 image from Lab 1
docker tag localhost:5000/internal/payments@${GOOD_DIGEST} \
           localhost:8080/payments/payments:v1.0.0
docker push localhost:8080/payments/payments:v1.0.0
```

In the UI you'll now see the image, its layers, its CVE scan (Harbor uses Trivy under the hood by default), and — once you sign it — its Sigstore signature artifact alongside.

### Step 4 — Sign the Harbor image, then enforce

```bash
# Resolve the digest in Harbor
HARBOR_DIGEST=$(docker inspect --format '{{index .RepoDigests 0}}' localhost:8080/payments/payments:v1.0.0 | cut -d@ -f2)

# Sign with the keypair from Lab 5
# COSIGN_REGISTRY_USERNAME=admin \
# COSIGN_REGISTRY_PASSWORD=Harbor12345 \
COSIGN_REGISTRY_REFERRERS_MODE=legacy \
    cosign sign --key cosign.key \
    localhost:8080/payments/payments@${HARBOR_DIGEST}

# Clean signatures with
# cosign clean --type=signature localhost:8080/payments/payments@${HARBOR_DIGEST}
# or:
# cosign clean --type=all --force \
#     --registry-username admin \
#     --registry-password Harbor12345 \
#     localhost:8080/payments/payments@${HARBOR_DIGEST}

# Try to pull an unsigned image — Harbor refuses
docker pull localhost:8080/payments/some-other-image:latest
# → error: image not signed

# A signed pull works
docker pull localhost:8080/payments/payments@${HARBOR_DIGEST}
```

> **IMPORTANT**: Harbor does not _verify_ the signature, you didn't give it your pubkey! It only checks if signed to allow pull! You have to verify yourself using `cosign verify`!

### Step 5 — Replication (high availability)

Harbor → System → Registries → New Endpoint → add a second Harbor (or any OCI registry). Then Replication Rules → set up a one-way mirror. Now if your primary Harbor goes down, you can repoint deployments at the replica with no image rebuild. This is the answer to risk #9 (registry availability).

### Production credential management — the short version

- **Never** store registry passwords in plain files. Robot accounts only, scoped to one project and one action (push _or_ pull).
- The signing keys (`cosign.key`) go in a KMS, not on a disk.
- TLS certificates for the registry itself go in a secret store and rotate via cert-manager / similar.
- The Harbor `admin` password is treated like the root password for your registry — long, unique, in a vault, used only for break-glass.

> Harbor's bigger features — replication topologies, OIDC integration, retention policies, garbage collection, the policy controller — are the same shape on the commercial registries (Quay, JFrog, ECR Enterprise). The point of doing this in Harbor is that you can see all the buttons, change them, see what they do, and write down the right defaults for your own org.

---

## Lab 7 — The Cooldown Principle

Module 2.3 told you to keep base images current — newer minor versions of a base image generally have fewer CVEs, so rebasing is the cheapest CVE reduction you can do. This module adds a twist that closes the circle.

If your CI auto-updates the moment a new version is published — `:latest` semantics, or Dependabot with no delay — you are choosing to consume the most recent code as soon as it appears. **The Trivy, tj-actions, Shai-Hulud, and XZ incidents all had a window between "malicious version published" and "community caught it" measured in hours to weeks.** Pull during that window and you have just deployed the compromise.

The **cooldown principle**: wait a defined period after a new version is published before automatically consuming it. The community absorbs the freshness risk; you absorb the supply-chain risk on the back end.

Concrete patterns:

- **Renovate cooldown** (the cleanest implementation):

  ```json5
  // renovate.json
  {
    packageRules: [
      {
        matchManagers: ["dockerfile", "docker-compose"],
        minimumReleaseAge: "14 days",
      },
      { matchManagers: ["npm"], minimumReleaseAge: "7 days" },
    ],
  }
  ```

  Renovate will refuse to open PRs for versions younger than the cooldown.

- **Dependabot** added a similar `cooldown` feature in 2024; the equivalent is:

  ```yaml
  # .github/dependabot.yml
  updates:
    - package-ecosystem: "docker"
      directory: "/"
      schedule: { interval: "weekly" }
      cooldown:
        default-days: 14
  ```

- **Manual policy** ("we update base images on the 1st and 15th of every month, never on the day a new version drops") works if your team is small enough to enforce it. It is what most organisations end up doing.

The cooldown number is a knob. 7 days catches almost everything that was caught by the community quickly (tj-actions, qix). 14 days catches the harder cases (Trivy 2026 was caught in days; XZ took weeks). 30 days is paranoid but defensible for high-value targets. Combine with CVE-aware exception logic: a critical patch may be worth taking immediately because the alternative is exposure to a known exploit. Most automation tools support an "ignore cooldown for security-flagged updates" mode.

**Full circle:** update often (Module 2.3), but with a cooldown (Module 2.5). Patch CVEs, but verify what you're patching to (Lab 5). Trust the registry as much as you would trust any other internet-facing dependency, which is to say: as little as possible.

---

# Teardown

```bash
# Stop the local registry and pinned deployments
cd local_registry
docker compose down --volumes
docker compose -f deploy/compose-tag.yaml down --volumes 2>/dev/null
docker compose -f deploy/compose-digest.yaml down --volumes 2>/dev/null

# Stop Harbor (if you ran Lab 6)
cd ../harbor/harbor 2>/dev/null && sudo docker compose down -v; cd -

# Remove locally tagged images
docker rmi localhost:5000/internal/payments:prod 2>/dev/null
docker rmi node:14.17.0 node:22-alpine 2>/dev/null

# Clean scan / SBOM artifacts
rm -rf sboms/ scans/ results.sarif grype-results.sarif

# Clean Harbor installer
rm -rf harbor/harbor harbor/harbor.tgz 2>/dev/null
```

---

# References

- **OCI specs** — <https://github.com/opencontainers> (image-spec, distribution-spec, runtime-spec)
- **Sigstore** — <https://docs.sigstore.dev/>
- **SLSA v1.0** — <https://slsa.dev/spec/v1.0/levels>
- **OpenSSF Best Practices for Containers** — <https://best.openssf.org/>
- **CISA Software Bill of Materials** — <https://www.cisa.gov/sbom>
- **Harbor docs** — <https://goharbor.io/docs/>
- **Renovate cooldown** — <https://docs.renovatebot.com/configuration-options/#minimumreleaseage>
- **Liz Rice, _Container Security_ (2nd ed., O'Reilly, 2025)** — chapters 7-8 are the canonical companion reading
- **Aqua Security, Trivy supply chain incident advisory (March 2026)** — GHSA-69fq-xp46-6x23
- **StepSecurity / GitHub joint write-up on `tj-actions/changed-files` (March 2025)**
- **Andres Freund, "backdoor in upstream xz/liblzma leading to ssh server compromise"** — oss-security@openwall, 29 March 2024
- **Unit 42 / Splunk / Microsoft writeups on Shai-Hulud and TeamPCP (September 2025 – May 2026)**
