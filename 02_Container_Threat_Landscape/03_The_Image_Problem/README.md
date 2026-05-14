# The Image Problem: Risks and Vulnerabilities of Container Images

Container image security is not a side topic. In modern platforms, the image is the software delivery unit, the deployment artifact, and a major part of the software supply chain. If the image is weak, stale, oversized, untrusted, or non-reproducible, the platform inherits that weakness before the container even starts.

This lecture uses the same course application story we will keep improving during the week: a small containerized application stack with a backend, frontend, and database. Here we focus on the backend image, because it is the easiest place to see how bad image hygiene turns into real security risk.







A safer image workflow should include:
Use trusted base images.
Pin image versions carefully.
Prefer immutable digests for critical workloads.
Scan images before deployment.
Rebuild images regularly.
Avoid stale base images.
Review Dockerfiles and build pipelines.
Avoid pulling random images directly into production.
Monitor upstream security advisories.








## Why The Image Is The Problem

When teams say "we run containers", what they often mean in practice is "we run whatever was baked into an image at build time". That image may contain:

- an outdated operating system snapshot
- vulnerable OS packages
- vulnerable application dependencies
- build tools that are no longer needed at runtime
- credentials, tokens, SSH keys, or internal files accidentally copied into the build context
- misleading metadata such as a mutable tag that no longer points to the image the team thinks it does
- no trustworthy proof of where the image came from or how it was built

An image is not just a zip file with an application inside it. It is a layered supply-chain artifact with identity, history, and metadata.

If you only look at `docker run myapp:latest`, you see almost none of that risk.

## What A Container Image Actually Is

At a high level, an OCI image is built from several pieces:

```text
registry.example.com/course/backend:1.0
        |
        +-- tag (mutable name)
              |
              +-- image index / manifest list (optional, often multi-platform)
                    |
                    +-- image manifest
                          |
                          +-- config JSON
                          +-- layer 1
                          +-- layer 2
                          +-- layer 3
```

The important security meaning of each piece is:

- `tag`: human-friendly, convenient, mutable, not trustworthy enough for exact identity
- `digest`: content-addressable identifier, immutable for that exact artifact
- `manifest`: points to the config and ordered layer list
- `config`: stores metadata such as entrypoint, env vars, labels, user, and image history
- `layers`: filesystem changesets applied in order to produce the final root filesystem

### Why Layers Matter

Layers are the reason image mistakes persist.

If you:

1. `COPY .env /app/.env`
2. `RUN rm /app/.env`

the file disappears from the final merged filesystem view, but it was still present in an earlier layer. OCI layers represent additions, modifications, and removals as changesets. Removals are represented through whiteouts, not by rewriting earlier layers out of existence.

Security consequence:

- "I deleted it later" is not a valid remediation if the image was already built
- anyone with access to the image layers or a saved tarball may still recover the deleted content
- registries, caches, CI artifacts, and other developers may already have the bad image

### Tags vs Digests

This is one of the most important practical distinctions in the entire course.

`backend:latest` does not identify one exact artifact. It identifies whatever artifact the registry currently maps to that tag.

`backend@sha256:...` identifies one exact artifact.

Security consequence:

- tags are good for human workflow
- digests are required for exact reproduction, precise rollback, and trustworthy deployment references

In 2026, a mature pipeline should treat digest-based identity as normal, not advanced.

## The Real Risk Categories

| Risk | What It Looks Like | Why It Matters | Better Direction |
| --- | --- | --- | --- |
| Untrusted source | Pulling random public images | Malicious content, weak maintenance, hidden dependencies | Prefer curated sources, official images, verified publishers, or internal approved registries |
| Mutable tags | `FROM python:latest` | Builds are non-reproducible and can drift silently | Pin version, and for production pin digest |
| Bloated base images | Full distro plus shells, package managers, editors, tools | Larger attack surface and more CVEs | Use the smallest supported runtime image that still fits operations |
| Stale images | Old base image never rebuilt | Known fixes never reach production | Rebuild continuously, not only when app code changes |
| Hidden baggage in build context | `COPY . .` from a messy repo | Internal files, notes, caches, test data, and secrets may enter the image | Use `.dockerignore` and copy only what is needed |
| Secrets in layers | Copying `.env`, private keys, or tokens during build | Secrets may persist in image history and exported layers | Use BuildKit secrets and keep secrets out of the context |
| Build tools in runtime | Compiler, shell, package manager, git left in production image | Increases post-exploitation options and image size | Use multi-stage builds or dedicated runtime images |
| No provenance | No proof of what source or builder produced the image | Harder to trust, audit, or gate deployments | Generate provenance and attach it to pushed images |
| No SBOM | No inventory of packaged components | Harder to triage CVEs and respond to incidents | Generate and retain SBOMs per build |
| No signature verification | Anybody can push "something" to a registry path if governance is weak | Consumers cannot verify publisher integrity | Sign images and verify at deploy time |
| Scanner overconfidence | "Trivy says zero criticals, so we are safe" | Misses misconfigs, malicious code, exploitability context, and some package edge cases | Treat scanning as necessary but insufficient |

## Demo 1: Inspect The Image Instead Of Trusting It

This first demo builds an intentionally weak backend image so we can inspect what is really inside it.

### Step 1: Move Into The Demo Folder

```bash
cd demo
```

### Step 2: Create A Local `.env` From The Example File

Linux or macOS:

```bash
cp .env.example .env
```

PowerShell:

```powershell
Copy-Item .env.example .env
```

### Step 3: Build The Insecure Image

```bash
docker build -f Dockerfile.insecure -t image-problem:insecure .
```

### Step 4: Inspect Basic Metadata

```bash
docker image inspect image-problem:insecure
docker image history --no-trunc image-problem:insecure
docker image ls image-problem:insecure
```

What to notice:

- the image was built as `root`
- it contains more than just the application
- the history shows a full command trail for each layer
- the total size is larger than it needs to be for a trivial Python service

### Step 5: Export The Image And Look At The Artifact

```bash
docker image save -o insecure-image.tar image-problem:insecure
mkdir extracted-image
tar -xf insecure-image.tar -C extracted-image
```

Now inspect the extracted image contents:

```bash
ls extracted-image
cat extracted-image/manifest.json
```

If you want to dig deeper, unpack the layer tar files and inspect them. The exact file names differ per build because they are content-addressed.

Key lesson:

- an image is a structured artifact with manifests, config, and layers
- you should be willing to inspect it the same way you would inspect a package, VM image, or signed binary

## Demo 2: Leak A Secret Into An Image Layer

Now we prove a common failure mode that appears constantly in real environments.

The insecure Dockerfile copies the whole build context, including `.env`, and then deletes `.env` in a later layer:

```dockerfile
COPY . .
RUN rm -f .env
```

That looks harmless to many developers. It is not.

### Step 1: Search The Exported Layers For The Training Secret

Linux or macOS:

```bash
grep -R "training-only-password" extracted-image
```

PowerShell:

```powershell
Get-ChildItem -Recurse extracted-image | Select-String "training-only-password"
```

Expected outcome:

- you should find the secret value in one of the extracted layer files even though `.env` was deleted later

### Why This Happens

The final container filesystem is a merged view of multiple layers.

Deleting a file in a later layer usually means:

- the later layer contains a removal marker
- the earlier layer still exists
- the artifact still contains the bytes you should never have shipped

### Why This Is Operationally Dangerous

If a bad image was:

- pushed to a registry
- cached in CI
- pulled by another developer
- used in a staging environment
- mirrored to another registry

then deleting the file in source control after the fact does not clean up the already-built artifact.

The remediation is usually:

1. rotate the secret
2. rebuild the image from a clean state
3. replace the bad image everywhere it was distributed
4. clean up registry and CI artifacts where possible

### A Subtle But Important Point

If `trivy` does not flag the training values in this demo as a secret, that is not a failure of the lecture. It is a useful lesson.

Secret scanning is extremely valuable, but it is pattern-based and heuristic-driven. Generic test values may not match a built-in rule. That does not make the image safe.

## Demo 3: Rebuild The Same App With A Hardened Image Approach

Now we build the same backend again, but we make different choices:

- smaller base image
- no `COPY . .`
- narrow build context via `Dockerfile.hardened.dockerignore`
- no `.env` in the build context
- no unnecessary shell tools or editors
- explicit non-root runtime user

### Step 1: Build The Hardened Image

```bash
docker build -f Dockerfile.hardened -t image-problem:hardened .
```

### Step 2: Compare The Two Images

```bash
docker image ls image-problem
docker image history --no-trunc image-problem:hardened
docker image history --no-trunc image-problem:insecure
```

What to notice:

- the hardened image should be smaller
- the hardened image copies only the application file
- the hardened image does not embed the demo `.env`
- the runtime user is no longer root
- the layer history is simpler and easier to reason about

### Step 3: Run The Hardened Image

```bash
docker run --rm -p 8080:8080 image-problem:hardened
```

In another terminal:

```bash
curl http://localhost:8080/
```

The response includes the runtime user ID so you can confirm the image is not running as root.

### Step 4: Scan Both Images

```bash
trivy image --scanners vuln,secret,misconfig image-problem:insecure
trivy image --scanners vuln,secret,misconfig image-problem:hardened
```

What to look for:

- package count differences
- severity distribution differences
- whether unnecessary files or metadata show up
- whether the hardened image is easier to triage

Do not oversell the result. Smaller and cleaner is better, but "fewer findings" is not the same thing as "secure".

## Optional Demo Extension: Safe Build-Time Secret Consumption

If a build must temporarily use a secret, do not use `ARG`, `ENV`, or `COPY`.

Use BuildKit secrets instead.

Create a local file that is not committed to source control:

Linux or macOS:

```bash
printf "training-only-token\n" > private-token.txt
```

PowerShell:

```powershell
Set-Content -Path private-token.txt -Value "training-only-token"
```

Build the optional example:

```bash
docker build -f Dockerfile.build-secrets \
  --secret id=demo_token,src=private-token.txt \
  -t image-problem:build-secret .
```

What this demonstrates:

- the secret is mounted only for the relevant `RUN` step
- it is not copied into the final image filesystem
- it avoids the very common anti-pattern of using build args for credentials

Delete the local secret file after the demo:

Linux or macOS:

```bash
rm private-token.txt
```

PowerShell:

```powershell
Remove-Item private-token.txt
```

## Images Best Practices

The secure baseline for image handling has moved. In a modern environment, the following controls are no longer "nice to have".

### 1. Start With A Governed Source

Prefer:

- official images from reputable maintainers
- verified publisher images
- internally curated base images
- approved registries with access control and retention policies

Do not normalize:

- random public images from personal namespaces
- abandoned images with no update cadence
- images built on unsupported or end-of-life distributions

### 2. Pin What You Mean

At minimum:

- pin a meaningful version tag

For production:

- pin the digest

Example:

```dockerfile
FROM python:3.12-slim-bookworm@sha256:<current-digest>
```

Useful commands:

```bash
docker buildx imagetools inspect python:3.12-slim-bookworm
docker pull python@sha256:<digest>
```

Practical guidance:

- developers can work with versioned tags during iteration
- CI should resolve and record exact digests
- deployments should reference digests for exact rollout and rollback

### 3. Minimize The Runtime Image

Smaller is not automatically secure, but smaller usually means:

- fewer packages to patch
- fewer libraries to scan
- fewer tools for an attacker after compromise
- less noise during triage

Reasonable approaches:

- slim base images
- distroless or hardened runtime images where they fit operations
- multi-stage builds so toolchains stay in builder stages

Tradeoff to teach explicitly:

- the more minimal the image, the harder interactive debugging may become
- mature teams often keep a separate debug image or debug workflow instead of bloating the production image

### 4. Treat Build Context As A Security Boundary

Most teams focus on the Dockerfile and ignore the context. That is a mistake.

The command:

```bash
docker build .
```

sends a build context. If the context is messy, the image build is already risky before the first instruction runs.

Common unwanted context content:

- `.env` files
- `.git` history
- editor backups
- local test data
- internal notes
- SSH keys
- package-manager credentials
- old backups and exports

The hardened demo uses a Dockerfile-specific ignore file that allow-lists only what the build actually needs. That is stronger than trying to maintain a long deny-list.

### 5. Never Pass Secrets Through `ARG`, `ENV`, Or `COPY`

This is one of the most important applied rules in the lecture.

Bad patterns:

- `ARG NPM_TOKEN=...`
- `ENV AWS_SECRET_ACCESS_KEY=...`
- `COPY .npmrc /root/.npmrc`
- `COPY .env /app/.env`

Better pattern:

- `RUN --mount=type=secret,...`

Even build arguments are unsafe for secrets. Depending on how they are used, they may be visible in image history and in provenance data generated by modern build systems.

### 6. Scan Early, Scan Late, And Re-Scan

A solid image security process scans:

- before build, to catch obvious context problems
- after build, to assess the actual image artifact
- in the registry, because vulnerabilities are discovered after images are pushed
- continuously, because yesterday's image may become today's incident

Good scanning workflow:

- developer scan for fast feedback
- CI scan for policy enforcement
- registry or platform scan for continuous re-evaluation

### 7. Generate SBOMs

An SBOM gives you a component inventory. That matters for:

- vulnerability triage
- incident response
- supplier communication
- proving what was shipped

With Docker Buildx:

```bash
docker buildx build --sbom -t registry.example.com/course/backend:1.0.0 --push .
```

Important nuance:

- SBOM and provenance attestations are most useful when pushed to a registry-backed workflow
- depending on the image store, local builds may not preserve attestations the way teams expect

### 8. Generate Provenance

Provenance answers questions such as:

- what source produced this image
- which builder created it
- what parameters were used
- whether the artifact matches the claimed build process

Example:

```bash
docker buildx build --provenance -t registry.example.com/course/backend:1.0.0 --push .
```

Why it matters:

- provenance makes policy and trust decisions more defensible
- it helps distinguish "we built this" from "we found this in a registry"

### 9. Sign Images And Verify Them Before Deployment

Signing proves publisher control over an artifact reference. Verification lets the platform reject artifacts that do not meet policy.

Example with `cosign`:

```bash
cosign sign registry.example.com/course/backend@sha256:<digest>
cosign verify registry.example.com/course/backend@sha256:<digest>
```

Practical guidance:

- sign the immutable digest, not just a tag
- verification should happen automatically in CI, admission control, or deploy pipelines
- signatures complement scanning and provenance; they do not replace them

Current ecosystem note:

- do not design new workflows around legacy Docker Content Trust assumptions
- modern image signing programs should center on Sigstore or Notation-style verification workflows

### 10. Rebuild Images Continuously

One of the most common image failures is simple neglect.

Teams often rebuild only when app code changes. That means:

- base image fixes are missed
- distro package fixes are missed
- scanner results become stale

Mature pattern:

- scheduled rebuilds even when app code is unchanged
- automatic pull requests or tickets when base image digests drift
- policy around maximum image age

## Container Image Scanning

Scanners are essential. They are not oracles.

Keep these rules in mind:

- CVE count is not exploitability
- severity may differ between vendor advisories and public databases
- third-party package sources can create false positives or false negatives
- "unfixed" does not mean "safe to ignore"; it means no vendor patch is available yet
- a secret scanner missing a value does not prove the artifact contains no sensitive data
- malware, logic bombs, or intentionally hostile code are not solved by CVE scanning alone

In other words:

- use scanners as evidence
- do not mistake scanner output for complete truth

## Minimum 2026 CI/CD Gate For Images

For a professional baseline, a pipeline for containerized workloads should do at least this:

1. Build with a pinned base version and refresh base metadata with `--pull`.
2. Scan the built image for vulnerabilities, secrets, and misconfigurations.
3. Fail the pipeline on policy-breaking findings, such as critical issues with fixes available or forbidden image properties.
4. Generate SBOM and provenance attestations.
5. Push the image to a governed registry.
6. Sign the pushed digest.
7. Enforce verification and image policy at deployment time.

Typical deployment policy checks:

- signature valid
- approved registry only
- digest-based image reference only
- no `:latest`
- image not older than allowed threshold
- no critical vulnerabilities with fixes available
- required provenance present

## Common Myths

| Myth | Reality |
| --- | --- |
| "If it runs, the image is fine." | Runtime success says very little about supply-chain trust or embedded risk. |
| "Official image means secure by default forever." | Official or trusted content is a better starting point, not a permanent security guarantee. |
| "I deleted the secret later in the Dockerfile." | The secret may still exist in a lower layer or exported image artifact. |
| "Using a small image means we solved image security." | Smaller helps, but provenance, scanning, digest pinning, and governance still matter. |
| "No critical CVEs means the image is safe." | CVEs are only one part of image risk. |
| "Tag pinning is enough for reproducibility." | Tags are mutable. Digests are the exact identity. |

## Practical Takeaways

- The image is a security artifact, not just a packaging convenience.
- Every `COPY`, `RUN`, and base image choice affects attack surface and trust.
- Build context mistakes are one of the fastest ways to leak sensitive data.
- Image history and layers matter as much as the final filesystem view.
- Tag-based identity is too weak for serious deployment control.
- Scanning is necessary, but provenance, SBOMs, and signatures are what turn scanning into a trustworthy pipeline.

## Suggested Discussion Prompts

- What is our organization's approved base image strategy?
- Who is allowed to introduce a new external image source?
- Do we currently deploy by tag or by digest?
- Where would we verify signatures or provenance in our pipeline?
- How would we rotate and contain secrets if a bad image had already been pushed?

## Exercises After The Lecture

1. Modify `Dockerfile.insecure` so it leaks a different file from the build context, then prove the leak via `docker image save`.
2. Convert the hardened image to a multi-stage build and compare size and package inventory again.
3. Add a CI job that fails on forbidden image properties such as `:latest` or running as root.
4. Push a test image to a registry, generate SBOM and provenance, and inspect the resulting attestations.
5. Sign the image digest and verify it before a deployment step.

## Connection To The Rest Of The Week

This lecture should change how participants think about the whole course stack.

From this point forward:

- the backend, frontend, and supporting services should not be treated as generic containers
- every image is part of the attack surface
- every image decision affects later topics such as registry security, runtime hardening, observability, and the final Defend The Flag exercise

Later modules will build on this:

- threat landscape: compromised or weak images as a delivery vector
- networking: same application stack, but now we focus on exposure and segmentation
- hardening: we keep the cleaner image practices and add runtime controls
- defend the flag: participants secure and validate the full environment, not just the code

## References And Further Reading

- OCI Image Format Specification: <https://github.com/opencontainers/image-spec>
- OCI layer changesets and whiteouts: <https://raw.githubusercontent.com/opencontainers/image-spec/main/layer.md>
- Docker image digests: <https://docs.docker.com/dhi/core-concepts/digests/>
- Docker build secrets: <https://docs.docker.com/build/building/secrets/>
- Docker Buildx `--sbom` and `--provenance`: <https://docs.docker.com/reference/cli/docker/buildx/build/>
- Docker image save: <https://docs.docker.com/reference/cli/docker/image/save/>
- Docker image inspect: <https://docs.docker.com/reference/cli/docker/image/inspect/>
- Docker trusted content and official images: <https://docs.docker.com/docker-hub/image-library/trusted-content/>
- Trivy container image scanning: <https://trivy.dev/v0.59/docs/target/container_image/>
- Trivy secret scanning: <https://trivy.dev/docs/latest/scanner/secret/>
- Trivy OS package caveats and vendor advisory model: <https://trivy.dev/v0.33/docs/vulnerability/detection/os/>
- Sigstore container signing with Cosign: <https://docs.sigstore.dev/cosign/signing/signing_with_containers/>
