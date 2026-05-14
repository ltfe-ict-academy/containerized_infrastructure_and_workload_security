# The Image Problem: Risks and Vulnerabilities of Container Images

## What Is A Container Image?

A container image is **a self-contained unit of packaging that includes every component required for an application to run**. Think of it as a pre-configured environment that ensures consistency across different systems. The image encapsulates:
- **Application Code**: The binary or source files of your software.
- **Dependencies**: Libraries, runtimes (like Python or Node.js), and environment variables.
- **OS Constructs**: A "stripped-down" version of an operating system (usually just the filesystem and basic utilities). The image does not include a kernel, as containers share the host OS kernel.

| Feature | Image | Container |
| --- | --- | --- | 
| Status | A "stopped" or static template (Build-time). | A running instance of an image (Run-time). |
| Mutability | Immutable: Once built, it does not change. | Mutable: Has a writable layer for temporary data. |
| Analogy | Similar to a VM Template or a Class in OOP. | Similar to a running VM or an Object instance. |

> Just as a VM template is a "frozen" version of a virtual machine, a Docker image is the static blueprint for a container.

![Container vs Image](./images/img01.png)

Source: Docker Deep Dive, Nigel Poulton

Images are constructed using a stacked layer system. Each instruction in a build file (like a Dockerfile) creates a new layer. These layers are read-only and stacked on top of each other to appear as a single unified object. This architecture allows for layer sharing, which saves disk space and speeds up downloads.

While Docker popularized the format, the industry now follows the **Open Container Initiative (OCI) standard**. This ensures portability across the ecosystem. You can build an image using Docker, but run it using Podman, containerd, or CRI-O without any modifications. If a tool is OCI-compliant, it will handle the image flawlessly.

## OCI Container Standards

The [Open Container Initiative (OCI)](https://opencontainers.org/) is a lightweight, open governance structure (project), formed under the auspices of the Linux Foundation, for the express purpose of creating open industry standards around container formats and runtimes. The OCI was launched on June 22nd 2015 by Docker, CoreOS and other leaders in the container industry. The OCI currently contains three specifications: 
- the Runtime Specification (runtime-spec), 
- the Image Specification (image-spec) 
- the Distribution Specification (distribution-spec).

> The OCI Distribution Spec allows for arbitrary content, not just container images, to be stored in a registry. As a result, registries are being used to hold other types of container-adjacent artifacts, including Helm charts, Open Policy Agent policies, Software Bill of Materials and attestations.

### Docker image versus OCI image

In daily language, people often say “Docker image” when they mean any container image. Historically this made sense because Docker popularized the image workflow. In modern environments, the more precise term is OCI image.

A Docker-built image can be OCI-compatible, and OCI-compatible images can be used by many runtimes and tools, not just Docker. Kubernetes commonly runs images through container runtimes such as `containerd` or `CRI-O`. Tools such as Podman, Buildah, Skopeo, nerdctl, Trivy, Syft, Grype, Cosign, and registry scanners all operate in this ecosystem.

This distinction matters because the security target is not “Docker” as a brand. The security target is the artifact format and lifecycle: how the image is built, what it contains, how it is identified, where it is stored, how it is verified, and what the runtime does with it.

## Inspecting OCI Images

At its core, an OCI-compliant container image consists of two primary parts: **the root filesystem (rootfs)** and the **image configuration**.

1. **The Root Filesystem (Layers)**: When you instantiate a container, the image provides the root filesystem that the container sees.
      - **Layered Design**: The filesystem is composed of an ordered set of layers. The base layer is applied first, and subsequent layers are stacked on top to produce the final layout.
      - **Building Layers**: Commands in a Dockerfile like FROM, ADD, COPY, or RUN modify the contents of this filesystem by creating new layers.

2. **The Configuration Metadata**: The image also contains metadata that defines how the container should behave at runtime.
      - **Runtime Instructions**: Commands like USER, EXPOSE, ENV, or ENTRYPOINT do not change the files on disk; instead, they update the image's JSON configuration.
      - **Inspection**: You can view this metadata by running `docker inspect <image_name>`.
      - **Example**: If you define an environment variable using ENV in a Dockerfile, that variable is stored in the config and automatically injected into the container process when it starts.
      - In Docker, the config information can be overridden at runtime using command-line parameters.


The OCI manifest acts as the "map" for the image, linking the configuration object to the specific layers required for a particular architecture and OS.


| Component   | Description  | Security & Operational Impact   |
| ----------- | ----------- | --------- |
| Tag         | A human-friendly name such as `1.0`, `3.12-slim`, or `latest`       | Mutable. Tags can be overwritten, meaning `latest` today might not be the same as `latest` tomorrow.  |
| Digest      | A unique SHA256 hash of the content.   | Immutable. Provides a cryptographically secure way to ensure you are running the exact same code every time.  |
| Image index | A higher-level object that can point to platform-specific manifests | Enables multi-architecture support (e.g., the same tag working on both `linux/amd64` and `linux/arm64`).   |
| Manifest    | The JSON document linking the config and layers.  | Defines the integrity of the image by listing the hashes of all constituent parts.   |
| Config JSON | Metadata including Env vars, User, and Cmd.   | Least Privilege: Reveals if a container is set to run as root by default or if sensitive data is hardcoded in Env variables. |
| Layers      | Ordered filesystem changesets.   | Persistence: Sensitive files (like SSH keys) added in one layer and deleted in another still exist in the image history.   |

[Skopeo](https://github.com/containers/skopeo) is a versatile command-line utility designed to perform operations on container images and repositories without requiring a background daemon like Docker. Its primary advantage is the ability to inspect remote images directly on a registry, allowing you to view manifests and configurations without downloading the entire image to your local disk.

To install Skopeo, run:
```bash
# For Debian/Ubuntu
sudo apt-get -y update
sudo apt-get install -y skopeo
```

We can generate an OCI image from a Docker image and check the contents:
```bash
skopeo copy docker://python:3.14-slim-bookworm oci:python-oci:3.14-slim-bookworm

ls python-oci/
```

The `index.json` file contains the manifest for the image, including the unique digest
that identifies it:
```bash
cat python-oci/index.json
```   

Example output:
```json
{
   "schemaVersion":2,
   "manifests":[
      {
         "mediaType":"application/vnd.oci.image.manifest.v1+json",
         "digest":"sha256:c0bbb2bfea3d552260f0d071f4ef9358d25b50c37d7a91895710cde507de4ade", 
         "size":1751,
         "annotations":{
            "org.opencontainers.image.ref.name":"3.14-slim-bookworm"
         }
      }
   ]
}
```

This digest matches one of the blobs in the OCI-format image. The blobs can be checked by running:
```bash
ls python-oci/blobs/sha256/
```

While the OCI layout is perfect for storage and transport, low-level runtimes like runc cannot execute a container directly from these hashed blobs. Instead, the image must be "unpacked" into an **OCI Runtime Bundle**. 

To see this in action, we can use [umoci](https://github.com/opencontainers/umoci), a tool specifically designed to manipulate OCI images and transform them into bundles.

```bash
# Install umoci
sudo apt-get -y install umoci

# Unpack the image into a runtime bundle
umoci unpack --image python-oci:3.14-slim-bookworm python-bundle --rootless

# View the bundle structure
ls python-bundle

# Output:
# config.json  rootfs  sha256_c0bbb2bfea3d552260f0d071f4ef9358d25b50c37d7a91895710cde507de4ade.mtree  umoci.json
```

By exploring the rootfs directory, we see the actual Linux filesystem that the container will perceive as its own:
```bash
ls python-bundle/rootfs
```

The unpacking process transforms the abstract blobs into two concrete components that the runtime understands:
- **The `rootfs/` Directory**: This is the result of flattening all the filesystem Layers into a single directory. It contains the binaries, libraries, and distribution files (like Python and its dependencies) in their uncompressed state.
 - **The `config.json` File**: This is generated from the Configuration blob. It tells the runtime exactly how to start the process, including namespaces, resource limits, and environment variables.

The OCI layout uses **Content Addressable Storage**, meaning every file is named after its own SHA256 hash. This creates a secure "Chain of Trust":
- `index.json` points to the Manifest blob.
- The **Manifest blob** acts as a map, containing the hashes for the **Config blob** and each ordered Layer blob.
- The Container Runtime follows these hashes to verify and pull the correct files from the `/blobs/sha256/` directory to reconstruct the application.

> Because every component is referenced by its unique Digest, it is impossible to alter a single byte in a layer or config file without breaking the chain. If a blob is tampered with, the hash will no longer match the manifest, and the runtime will refuse to execute the container.

When you look at the extracts from the bundle, you are seeing the direct translation of image metadata into operating system instructions.
```bash
cat python-bundle/config.json
```

- **The Root Path**: This tells the runtime (like `runc`) where to find the unpacked filesystem. Once the container starts, the runtime will use the `pivot_root` or `chroot` system call to make this specific directory appear as the `/` (root) directory for the containerized process.
```json
"root": {
   "path": "rootfs"
}
```

- **Mounts**: Containers need access to certain kernel interfaces to function. The configuration explicitly defines where to mount pseudofilesystems like `/proc` (for process information) and `cgroups` (for resource management). This ensures the container can "see" its own limited view of the system hardware.
```json
"mounts": [
  {
    "destination": "/proc",
    "type": "proc",
    "source": "proc"
  },
  ...
```

- **Isolation via Namespaces**: This is where the magic of isolation happens. This section tells the kernel to wrap the process in specific namespaces. For example:
   - PID: The process will think it is PID 1.
   - Network: The process gets its own virtual network stack.
   - Mount: The process has its own private list of mount points.
```json
"namespaces": [
  { "type": "pid" },
  { "type": "network" },
  { "type": "ipc" },
  ...
]
```

> In Docker we can inspect the image configuration with `sudo docker pull python:3.14-slim-bookworm && sudo docker image inspect python:3.14-slim-bookworm`. 


---
https://chatgpt.com/g/g-p-6a05bbc989148191b3eace3ab72144bf-pesco-container-security/c/6a05c1c3-758c-8326-a312-ea39905455c6?tab=sources

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




## Why The Image Is The Problem

- we do demos for each of the problems

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




## Image naming and tagging
- Pin image versions carefully. -> shows tags difference, tags can change, hashes vs tags, how to get the digest, how to use it in a Dockerfile.
- Prefer immutable digests for critical workloads.

### Tags vs Digests

This is one of the most important practical distinctions in the entire course.

`backend:latest` does not identify one exact artifact. It identifies whatever artifact the registry currently maps to that tag.

`backend@sha256:...` identifies one exact artifact.

Security consequence:

- tags are good for human workflow
- digests are required for exact reproduction, precise rollback, and trustworthy deployment references

In 2026, a mature pipeline should treat digest-based identity as normal, not advanced.


## Inspecting Images



<!-- ### Step 1: Move Into The Demo Folder

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
- the total size is larger than it needs to be for a trivial Python service  -->

<!-- ### Step 5: Export The Image And Look At The Artifact

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
- you should be willing to inspect it the same way you would inspect a package, VM image, or signed binary -->

## Selecting Base Images
- Use trusted base images. -> show how easy is to get a bad image, docker official images, hardened images, curated internal images.
- inspecting images
- Avoid stale base images.
- schech image, alpine, mininal images


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

## Docker Build
- docker build, buildx, and BuildKit are the main tools for building images
- https://docs.docker.com/build/concepts/overview/

<!-- 
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

The hardened demo uses a Dockerfile-specific ignore file that allow-lists only what the build actually needs. That is stronger than trying to maintain a long deny-list. -->


## Dockerfiles and Build Best Practices
- docker file is a build script, not a recipe for a final image
- include the dockerfile best practices https://docs.docker.com/reference/dockerfile/#add
- https://github.com/ltfe-ict-academy/cloud-docker-kubernetes/tree/main/Part_06_Building_Images


possible problems do mantion
using untrusted public base images
using large full-OS images when a smaller image would be enough
stale packages and vulnerable libraries
unnecessary shells, package managers, compilers, curl, wget, or debugging tools
SSH servers inside production containers
images that run as root by default
secrets copied into image layers
sensitive files included through a broad build context
missing or weak .dockerignore
unverified downloads in the Dockerfile
curl | sh installation patterns
mutable tags such as latest
missing image signing or provenance
vulnerable application dependencies baked into the image

<!-- ### 2. Pin What You Mean

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
- deployments should reference digests for exact rollout and rollback -->




<!-- ### Demo 2: Leak A Secret Into An Image Layer

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

Secret scanning is extremely valuable, but it is pattern-based and heuristic-driven. Generic test values may not match a built-in rule. That does not make the image safe. -->

<!-- ## Demo 3: Rebuild The Same App With A Hardened Image Approach

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
``` -->


<!-- ### 5. Never Pass Secrets Through `ARG`, `ENV`, Or `COPY`

This is one of the most important applied rules in the lecture.

Bad patterns:

- `ARG NPM_TOKEN=...`
- `ENV AWS_SECRET_ACCESS_KEY=...`
- `COPY .npmrc /root/.npmrc`
- `COPY .env /app/.env`

Better pattern:

- `RUN --mount=type=secret,...`

Even build arguments are unsafe for secrets. Depending on how they are used, they may be visible in image history and in provenance data generated by modern build systems. -->


<!-- 
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
 -->



## Generating SBOMs

<!-- ### 6. Scan Early, Scan Late, And Re-Scan

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
- depending on the image store, local builds may not preserve attestations the way teams expect -->



## Image Security Scanning
- Scan images before deployment.

<!-- 
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
- do not mistake scanner output for complete truth -->




## General best practices for images


<!-- 
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
- modern image signing programs should center on Sigstore or Notation-style verification workflows -->
<!-- 
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
- required provenance present -->


- Rebuild images regularly.
- Review Dockerfiles and build pipelines.
- Avoid pulling random images directly into production.
- Monitor upstream security advisories.

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
















