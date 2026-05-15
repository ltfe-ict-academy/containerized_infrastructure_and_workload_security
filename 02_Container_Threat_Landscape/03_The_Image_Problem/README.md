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

## Why The Image Is The Problem

When a team says, “We run containers,” what they often mean in practice is: **We run whatever was baked into an image at build time.**

That image may contain:
- an outdated operating system snapshot
- vulnerable OS packages
- vulnerable language dependencies
- unnecessary shells, package managers, compilers, and debugging tools
- credentials or internal files accidentally copied from the build context
- a default runtime user of root
- broad metadata, labels, environment variables, and build history
- an old base image that has not been rebuilt since new CVEs were published
- no SBOM, no signature, no provenance, and no clear ownership

**If the image runs, that does not mean the image is fine.** Images have memory. Build steps, layers, metadata, copied files, and package manager artifacts can preserve information long after the final container appears to work correctly.

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

## Image Layers

Layers are one of the most critical concepts in container architecture, particularly for optimization and security.

An image filesystem is built by stacking these layers on top of each other. Each layer represents a precise set of changes relative to its parent layer: files added, files modified, or files removed. The OCI configuration specification describes an image as an ordered collection of these filesystem changesets combined with execution parameters (like entrypoints, environment variables, and labels).

A simplified conceptual view of an image looks like this:

```
Layer 5: Set user and command  (Metadata only)
Layer 4: Install dependencies  (Filesystem changes)
Layer 3: Copy application      (Filesystem changes)
Layer 2: Install Python        (Filesystem changes)
Layer 1: Base OS files         (Base layer)
```

![Image Layers](./images/img02.png)

Source: Docker Deep Dive, Nigel Poulton

At runtime, the container runtime merges these separate layer archives into a single, unified filesystem view. To the application running inside the container, it feels like a standard, flat directory structure, even though it is backed by loosely-connected, read-only layers. Because layers are independent, **multiple images can and often do share the same base layers, leading to massive space efficiencies across your system**.

### Inspecting Image Layers

There are three primary ways to inspect the layers that make up an image:

1. **During an Image Pull**: When you download an image, you can watch the layers pull in real time. Each line ending in "Pull complete" is a distinct layer being downloaded and extracted.
   ```bash
   sudo docker image pull redis:latest
   ```

2. **Using `docker image inspect`**: This command provides low-level cryptographic details about the image, including the specific content hashes (DiffIDs) of the filesystem layers.
   ```bash
   sudo docker image inspect redis:latest
   ```

3. **Using `docker history`**: This command displays the build history of the image. Note that it is not a strict list of filesystem layers; some Dockerfile instructions (like `ENV`, `EXPOSE`, or `CMD`) only add configuration metadata and do not result in a physical layer.
   ```bash
   sudo docker image history redis:latest
   ```

### Images vs. Containers: The Writable Layer

The fundamental difference between a container and an image is a **single thin layer added to the very top of the stack: [the writable container layer](https://docs.docker.com/engine/storage/drivers/)**.

![Container Layer](./images/img03.jpg)

Source: https://docs.docker.com/storage/storagedriver/

While **all underlying image layers are strictly read-only**, the container layer enables all read/write operations for a active instance.
- **Short-lived Nature**: This writable layer lives on the Docker host's filesystem (typically under `/var/lib/docker/<storage-driver>/...`). It is tightly bound to the lifecycle of the container. If the container is deleted, its writable layer is permanently destroyed, while the underlying image remains completely unchanged.
- **Multi-Tenancy**: Because each container maintains its own separate writable layer, multiple running containers can simultaneously share access to the exact same underlying image while maintaining their own unique data states.

![Multi-Tenancy](./images/img04.webp)

Source: https://docs.docker.com/storage/storagedriver/

If an application inside a container needs to modify an existing file that belongs to a read-only image layer, [Docker uses a **copy-on-write strategy**](https://docs.docker.com/engine/storage/drivers/#the-copy-on-write-cow-strategy):
1. The filesystem detects the write request on a lower layer file.
2. It instantly copies that file up into the container's thin writable layer.
3. The container modifies the copy in the writable layer, seamlessly hiding the original file beneath it.

This layer management is handled by [Linux storage drivers](https://docs.docker.com/engine/storage/drivers/select-storage-driver/) (such as `overlay2`, `fuse-overlayfs`, `btrfs`, or `zfs`). While storage drivers are highly space-efficient, copy-on-write operations **introduce performance overhead for write-intensive applications (like databases)**.

> Never use the container's writable layer for heavy I/O or persistent data. Always use Docker Volumes for write-intensive applications to bypass the storage driver and achieve native performance.

### Why "Deleted" Files Still Matter

A common security mistake occurs when developers treat a Dockerfile like a standard shell script. Consider this example:
```bash
mkdir image-layer-demo
cd image-layer-demo

# Create a fake .env file with a secret value
cat > .env <<'EOF'
DATABASE_PASSWORD=training-only-password
EOF

# Create an intentionally bad Dockerfile:
cat > Dockerfile <<'EOF'
FROM alpine:3.23
WORKDIR /app
COPY . .
RUN rm -f .env
CMD ["sh", "-c", "ls -la /app && sleep 3600"]
EOF

# Build the image
sudo docker build -t image-problem:layer-leak .

# Run the image and notice that .env is not visible:
sudo docker run --rm image-problem:layer-leak
```

It is a common misconception that `/app/.env` is safely erased because it does not appear in the final running container. It is not safe.

Because OCI layers are immutable changesets, a file removal does not delete the data from previous layers. Instead, the `rm` command creates a whiteout marker - an empty file with a `.wh.` prefix signifying that the path should be hidden from that point forward.

Now export the image and search the artifact:
```bash
sudo docker image save -o layer-leak.tar image-problem:layer-leak
mkdir extracted
sudo tar -xf layer-leak.tar -C extracted

# Create a directory to hold the actual recovered files
mkdir recovered_contents

# Find all compressed layer blobs and extract them into that directory
find extracted/blobs/sha256/ -type f -exec tar -xzf {} -C recovered_contents 2>/dev/null \;

# View your successfully stolen secret
cat recovered_contents/app/.env

# Confirm the file is still there even though it was "deleted" in the Dockerfile
ls -la recovered_contents/app/
# total 16
# drwxr-xr-x  2 administrator administrator 4096 May 15 09:35 .
# drwxrwxr-x 20 administrator administrator 4096 May 15 09:45 ..
# -rw-rw-r--  1 administrator administrator  100 May 15 09:35 Dockerfile
# -rw-rw-r--  1 administrator administrator   41 May 15 09:34 .env
# ----------  1 administrator administrator    0 Jan  1  1970 .wh..env
```

The sensitive file is hidden from the final merged filesystem view, but the raw bytes still exist entirely intact within the tarball of Layer 1. Anyone with access to the image archive, the container registry, or the CI/CD cache can easily extract the lower layer and recover the secret.
- "I deleted it later" is not a valid remediation for a leaked secret.
- If an image containing a secret was pushed to a registry, assume that secret has been compromised.
- Remediation: Rotate the secret immediately, use multi-stage builds to avoid copying secrets into intermediate layers, and rebuild your images from a clean state.

## Image naming and tagging

Image names look simple on the surface, but the way you reference them hides critical trust and security decisions. A fully qualified image reference follows this structure:
```
[registry]/[namespace]/[repository]:[tag]@[digest]
```

Examples:
- `nginx:1.27` (Implies Docker Hub registry and library namespace)
- `docker.io/library/nginx:1.27` (Explicit version of the same image)
- `registry.example.com/course/backend:1.0.0` (Private registry reference)
- `registry.example.com/course/backend@sha256` (Referenced strictly by digest)
- `registry.example.com/course/backend:1.0.0@sha256` (Referenced by both tag and digest)

The most critical distinction when managing container lifecycles is understanding that tags represent names, while digests represent identity.


| Feature   | Image Tag (:1.0.0)  | Image Digest (@sha256:...)   |
| ----------- | ----------- | --------- |
| **What it is** | A human-readable pointer or alias. | A unique, cryptographic SHA256 hash of the content. |
| **Mutability** | Mutable: Can be moved to point to a completely different image artifact. | Immutable: Uniquely ties to one specific layout of layers and config. It can never change. |
| **Analogy** | Like a Git branch name (e.g., main or dev) which moves as new commits are added. | Like a specific Git commit hash. It points to a precise moment in time. |

When you pull `backend:latest`, you are not identifying an exact artifact. You are pulling whatever image the registry currently maps to that tag. If someone pushes a new build to that tag five minutes later, the "latest" image changes.

When you **pull an image by its digest**, you guarantee that you are fetching the exact same bits every single time. Even if a developer overwrites a tag on the registry, the digest remains a permanent reference to that specific artifact.


Imagine you are running a production stack using a Docker Compose file distributed across three different backend servers:

```yaml
services:
  web:
    image: registry.example.com/course/backend:1.0.0
    ports:
      - "8080:8080"
```

If a developer accidentally overwrites the `1.0.0` tag in the registry with a buggy build, look at what happens over time:
   - Server A already has the old `1.0.0` cached locally and keeps running the stable code.
   - Server B crashes, restarts, pulls `1.0.0` fresh from the registry, and gets the buggy code.
   - Server C is a brand new server added to handle traffic logs, pulls `1.0.0`, and gets the buggy code.

Even though all three servers look identical in your Docker Compose file, they are now running completely different software configurations.

By **pinning your production environments to a digest, you eliminate tag drift**. If a tag changes on the registry, Docker will ignore the tag change and pull exactly what the cryptographic hash dictates. Also the risk for supply chain attacks is reduced, because if an attacker compromises the registry and pushes a malicious image to a commonly used tag, your production environment will not be affected if it is pinned to a digest.

```yaml
services:
  web:
    # Human-readable tag + strict digest validation
    image: registry.example.com/course/backend:1.0.0@sha256:45b23dee08af5e43...
    ports:
      - "8080:8080"
```

> When both a tag and a digest are provided, Docker prioritizes the digest for the pull operation.

### Practical Commands

1. **View the Immutable Repo Digest Locally**: After pulling a standard tagged image, you can find its cryptographic identity using docker image inspect:
   ```bash
   sudo docker pull alpine:3.23
   sudo docker image inspect alpine:3.23 --format '{{json .RepoDigests}}'
   ```

2. **Inspect Multi-Platform Image Indexes**: Many modern images contain sub-manifests for different architectures (like amd64 and arm64). You can inspect the root index digest using:
   ```bash
   sudo docker buildx imagetools inspect alpine:3.23
   ```

3. **Hardcoding Digests into Your Workflows**: To secure your builds, use digests right inside your Dockerfile:
   ```dockerfile
   FROM alpine:3.23@sha256:48d9183eb12a0535fbc24a101ee981f92e0df400810db69ef2dbf1e31d3f972b
   ```

Best practices for image referencing:
- **Local Development**: Version tags (like :3.12-slim) are perfectly acceptable for speed and convenience.
- **CI/CD Pipelines**: Use automated scripts to resolve your tags to their underlying SHA256 digests before shipping.
- **Production Environments**: Always deploy by digest. Never allow unpinned images or general environment tags like :latest in production environments, as they break your rollback capability and blindside container auditing.

## Selecting Base Images

The base image is the foundation of the final image. If the base is stale, bloated, untrusted, unsupported, or malicious, everything built on top inherits that problem.

[Docker’s build best-practices documentation](https://docs.docker.com/build/building/best-practices/#choose-the-right-base-image) puts base image selection first: **choose an image from a trusted source and keep it small**. 
- **Docker Official Images** are a curated collection that have clear documentation, promote best practices, and are regularly updated. They provide a trusted starting point for many applications.
- **Verified Publisher images** are high-quality images published and maintained by the organizations partnering with Docker, with Docker verifying the authenticity of the content in their repositories.
- **Docker-Sponsored Open Source** images are published and maintained by open source projects sponsored by Docker through an open source program.

When building your own image from a Dockerfile, ensure you choose a minimal base image that matches your requirements. **A smaller base image not only offers portability and fast downloads, but also shrinks the size of your image and minimizes the number of vulnerabilities introduced through the dependencies.**

**Prefer:**
- official images from reputable maintainers
- verified publisher images
- internally curated base images
- hardened images maintained by your platform team
- approved private registries with access control
- images with documented update cadence and support lifecycle

**Avoid:**
- random public images from personal namespaces
- images with no Dockerfile or source repository
- abandoned images
- unsupported or end-of-life distributions
- images that require running as root without explanation
- images that install an SSH server for production use
- images with unclear licensing or provenance

A base image decision is not only a developer convenience decision. It is a supply-chain decision.

Smaller images are usually easier to secure because they have fewer packages, fewer libraries, fewer utilities, and fewer scanner findings. But minimal images have tradeoffs.

| Base Type               | Strength                                           | Tradeoff                                                         |
| ----------------------- | -------------------------------------------------- | ---------------------------------------------------------------- |
| Full distribution image | Familiar tools, easy debugging                     | Large attack surface, many packages                              |
| Slim image              | Smaller, still operationally familiar              | May still include shell and package manager                      |
| Alpine                  | Very small, common for simple workloads            | Uses musl libc, which can cause compatibility differences        |
| Distroless              | No package manager or shell, small runtime surface | Harder interactive debugging                                     |
| `scratch`               | Empty base, excellent for static binaries          | You must provide everything needed, such as CA certs if required |
| Hardened vendor image   | Curated, patched, often signed and documented      | Vendor lock-in, subscription, or operational constraints         |

**Use the smallest supported runtime image that your team can operate safely.**

**Base image checklist:**
- Who maintains it?
- How often is it rebuilt?
- What distribution and version is it based on?
- Is the distribution still supported?
- Is there a public Dockerfile or build recipe?
- Does it run as root by default?
- Does it include a shell, package manager, compiler, SSH server, or debugging tools?
- Is it signed?
- Does it publish SBOMs or provenance?
- Can we pin it by digest?
- Can our scanners correctly identify its packages?
- Do we have a plan for rebuilding when the base digest changes?

### Using Docker Hardened Images

[Docker Hardened Images (DHI)](https://docs.docker.com/dhi/) provide minimal, secure, and production-ready container images, Helm charts, and system packages maintained by Docker. Designed to reduce vulnerabilities and simplify compliance.

You can pull and run a DHI like any other Docker image. Note that Docker Hardened Images are designed to be minimal and secure, so they may not include all the tools or libraries you expect in a typical image.

> **[Considerations when adopting DHIs](https://docs.docker.com/dhi/how-to/use/#considerations-when-adopting-dhis)**: Docker Hardened Images are intentionally minimal to improve security. If you're updating existing Dockerfiles or frameworks to use DHIs, keep in mind that runtime images don't include shells or package managers, run as non-root users by default, and may have different configurations than images you're familiar with.

Copmare the DHI with a standard image:

```bash
# Create a free Docker Hub account and login in to pull the DHI
sudo docker login dhi.io

# Pull the DHI and a standard image for comparison
sudo docker pull dhi.io/python:3.13
sudo docker pull python:3.13

# Run the image to confirm everything works:
sudo docker run --rm dhi.io/python:3.13 python -c "print('Hello from DHI')"
sudo docker run --rm python:3.13 python -c "print('Hello from standard image')"

# Compare the images:
sudo docker image ls dhi.io/python:3.13
sudo docker image ls python:3.13

sudo docker history dhi.io/python:3.13
sudo docker history python:3.13
```

Let's explore the differences in the image with the [`dive`](https://github.com/wagoodman/dive) tool:

```bash
# Install dive
DIVE_VERSION=$(curl -sL "https://api.github.com/repos/wagoodman/dive/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
curl -fOL "https://github.com/wagoodman/dive/releases/download/v${DIVE_VERSION}/dive_${DIVE_VERSION}_linux_amd64.deb"
sudo apt install ./dive_${DIVE_VERSION}_linux_amd64.deb

# Inspect the standard image visually
sudo dive python:3.13

# Inspect the DHI image visually
sudo dive dhi.io/python:3.13
```

### Using the `scratch` and the "distroless" base images

When packaging compiled binaries for production, minimizing the container's footprint is one of the most effective ways to optimize performance and harden security. Two primary strategies exist for creating these ultra-lean environments: building completely **[from scratch](https://docs.docker.com/build/building/base-images/#create-a-base-image)** or utilizing **[Google's "distroless"](https://github.com/GoogleContainerTools/distroless)** base images.

While both approaches eliminate standard operating system bloat, they serve slightly different needs in production workflows.


| Feature    | `FROM scratch`  | `FROM gcr.io/distroless/static-debian13`   |
| --------------- | --------- | ---------- |
| **Base Size** | 0 bytes  | ~2 MB to 3 MB   |
| **OS Packages**  | None   | None  |
| **System Libraries**  | None (Requires purely static binaries)   | Common minimal runtime dependencies (glibc, libssl)  |
| **SSL/TLS Certificates**  | No (Must be manually copied if needed) | Yes (Pre-installed and updated)    |
| **User Management** | No `/etc/passwd` (Runs as root by default)  | Includes a non-root user (`nobody:nogroup`, UID 65534) |
| **Primary Language**  | Go, Rust (Purely static compiled languages)    | C, C++, Rust, Go, or dynamic runtimes (Node/Python)       |


- **Dockerfile Example (`scratch`):** `scratch` is an explicitly empty starting point. It contains absolutely nothing - no shell, no libraries, no users, and no SSL certificates. If your application needs to make an HTTPS request, it will fail unless you manually bundle the root certificates. To use `scratch`, you must build your binary inside a build container using a multi-stage workflow, ensuring that your compiler outputs a completely self-contained, statically linked binary.

```bash
# Create a simple application file
cat > main.go <<'EOF'
package main

import "fmt"

func main() {
    fmt.Println("Hello from a completely empty container!")
}
EOF

# Create a Dockerfile that builds the binary and then packages it from scratch
cat > Dockerfile <<'EOF'
# Stage 1: The Build Environment
FROM golang:1.24-bookworm AS builder
WORKDIR /app
COPY main.go .
# Disable CGO to force a purely static binary
RUN CGO_ENABLED=0 GOOS=linux go build -o myapp main.go

# Stage 2: The Final Razor-Thin Image
FROM scratch
# Manually bring over SSL certs so our binary can make HTTPS calls
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app/myapp /myapp
ENTRYPOINT ["/myapp"]
EOF

# Build the image
sudo docker build -t myapp:scratch .

# Run the image
sudo docker run --rm myapp:scratch

# Check the image with dive
sudo dive myapp:scratch
```

- **Dockerfile Example (`distroless/static`)**: "Distroless" images, maintained by Google, restrict the runtime environment to only your application and its dependencies. They contain no package managers, shells, or standard terminal utilities. However, unlike `scratch`, they include critical system abstractions that production applications rely on, such as timezone data, SSL/TLS certificates, standard C libraries (`glibc`), and pre-configured non-root system users. Because the base image includes standard system prerequisites, your multi-stage setup becomes much cleaner and less prone to runtime crashes.

```bash
# Create a Dockerfile that builds the binary and then packages it with distroless
cat > Dockerfile.distroless <<'EOF'
# Stage 1: The Build Environment
FROM golang:1.24-bookworm AS builder
WORKDIR /app
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux go build -o myapp main.go

# Stage 2: The Production Image
# 'static' is the smallest distroless variant, designed for static binaries
FROM gcr.io/distroless/static-debian13:latest
COPY --from=builder /app/myapp /myapp
# Automatically switches to a secure, non-root user included in the base image
USER 65534:65534
ENTRYPOINT ["/myapp"]
EOF

# Build the image
sudo docker build -f Dockerfile.distroless -t myapp:distroless .

# Run the image
sudo docker run --rm myapp:distroless

# Check the image with dive
sudo dive myapp:distroless
```
If we inspect both resulting production images using tools like docker image ls or a low-level filesystem extraction, the differences become visually clear.
- The `scratch` image consists of a single layer containing just your binary file (and your manually copied certificates). It has no concept of file ownership outside of what you explicitly configure.
- The `distroless` image provides a small foundational layer that sets up standard Unix paths like `/etc`, `/var`, and `/tmp`, maps a default non-privileged user profile, and keeps system root certificates updated automatically through upstreams like Debian.

While FROM scratch offers the absolute theoretical minimum attack surface, **"distroless" is generally the superior choice for enterprise production binaries**:
1. **Security by Default (Non-Root Execution)**_ Running a container as the root user is a critical vulnerability. In a scratch container, configuring a custom non-root user requires manually generating and copying `/etc/passwd` files into the image. Distroless images ship with a secure nobody user built-in, making risk mitigation as simple as adding `USER 65534:65534` to your Dockerfile.
2. **Maintenance and Compliance**: Production applications constantly interact with the outside world via TLS/SSL. If you choose scratch, you are responsible for manually updating root certificates every time an automated image build triggers. Distroless base images handle this up-stream; simply pulling the latest base patch automatically patches underlying certificate authorities and critical system libraries.
3. **Dynamic Linking Compatibility**: Many compiled binaries still rely on standard system bindings (like `glibc` for network lookups or cryptographic tasks). Compiling with `CGO_ENABLED=0` works perfectly for pure Go or Rust, but if your code pulls in a legacy C library, a scratch container will immediately crash with a misleading file not found error. Distroless provides specific variants (like `distroless/base`) that include `glibc`, giving you the safety of a shell-less image without sacrificing system library access.

> Use scratch only when you are deploying an entirely autonomous utility that requires no OS primitives, no network certificates, and no external library bindings. For everything else, default to distroless to ensure standard operational compliance, user isolation, and maintainability.

## Docker Build

Modern Docker Build uses Buildx as the client and BuildKit as the builder backend. Docker’s documentation describes Docker Build as a client-server architecture: Buildx is the user interface for running and managing builds, while BuildKit executes the build steps. When you run docker build, you are using Buildx to send a build request to BuildKit.




---





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
















