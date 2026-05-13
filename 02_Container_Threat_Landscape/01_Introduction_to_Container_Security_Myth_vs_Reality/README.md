# Introduction to Container Security: Myth vs. Reality

Containers are often introduced as a simple way to package and run applications. That simplicity is one of their biggest strengths, but it also creates one of the most common security misunderstandings: the belief that anything running “inside Docker” is automatically isolated, safe, and unable to affect the host.

A Linux container is not a full virtual machine. It does not normally bring its own kernel. Instead, Docker uses Linux kernel features such as namespaces, control groups, capabilities, seccomp, and security modules to isolate and restrict processes. Docker’s own documentation describes namespaces as the first and most straightforward form of isolation, while also pointing out that Docker security depends on several areas: the kernel, the Docker daemon attack surface, container configuration, and hardening features.

> If you have an unknown binary, would you feel safe running it inside Docker? Safer depends on the container configuration, the host, the runtime, the image, the kernel, and what the container can access.

## Myth 1: Containers are lightweight virtual machines

A virtual machine usually has its own kernel. A Linux container does not. A Linux container is a process, or a group of processes, isolated with kernel features such as namespaces, cgroups, capabilities, seccomp, and Linux security modules like AppArmor or SELinux. This distinction matters because a VM-style mental model makes people overestimate the security boundary. If a VM is compromised, the attacker usually still needs a hypervisor escape to reach the host. If a container is compromised, the attacker is already running code on the host kernel, just with restrictions. [Docker’s documentation explains](https://docs.docker.com/engine/security) that when a container starts, Docker creates namespaces and control groups for the container. Namespaces provide isolation, and cgroups control resource usage.

- Run on the host: `uname -a`
- Run inside a container: `sudo docker run --rm alpine uname -a`

On a native Linux Docker host, both commands usually show the same kernel. The container has its own filesystem view and process namespace, but it is still using the host kernel.

Run: `sudo docker run --rm alpine sh -c 'hostname && ps aux'`

The output looks isolated. The process list is small. The hostname is container-specific. This is useful isolation, but it is not the same as a VM boundary. The practical implication is simple: when a container is compromised, the attacker is already running code on the same kernel as the host. The security question becomes: what exactly is that code allowed to do?

## Myth 2: Containers are secure by default

Docker does include important default protections. For example, [Docker’s default seccomp profile](https://docs.docker.com/engine/security/seccomp/) blocks around 44 system calls out of more than 300 while trying to preserve application compatibility. Seccomp is useful because it reduces what containerized processes can ask the kernel to do. However, defaults can be weakened or bypassed by configuration. A container can be started with additional capabilities, disabled seccomp rules, host filesystem mounts, host networking, privileged mode, or access to the Docker daemon. Useful defaults do not mean a secure deployment.

- Check the security options enabled on a Docker host: `sudo docker info --format '{{json .SecurityOptions}}'`
- Check whether a running container sees seccomp enabled: 
  - `sudo docker run --rm alpine sh -c 'grep Seccomp /proc/self/status'`
  - The output confirms that the container is running in Seccomp Mode 2, meaning it is actively filtered by a custom security profile rather than being unrestricted. The presence of one filter indicates that Docker's default security policy is successfully intercepting system calls to prevent unauthorized or dangerous kernel actions.

The important lesson is that container security starts with defaults, but it does not end there.

## Myth 3: Root inside a container is harmless

Root inside a container is restricted by the container boundary, but it is still root inside that environment. That distinction matters. The risk becomes obvious when host resources are mounted into the container. Docker bind mounts allow a file or directory from the host to appear inside the container. Docker documents bind mounts as a way to mount host filesystem paths into containers.

Create a test directory on the host:
```bash
mkdir -p /tmp/container-security-demo
echo "created on host" > /tmp/container-security-demo/host-file.txt
ls -ln /tmp/container-security-demo
```

Run a container as root and mount that directory:
```bash
sudo docker run --rm \
  -v /tmp/container-security-demo:/demo \
  alpine sh -c 'id && echo "created by root in container" > /demo/container-file.txt && ls -ln /demo'

# Check the host again:
ls -ln /tmp/container-security-demo
cat /tmp/container-security-demo/container-file.txt
```

The container wrote directly into a host directory. This is not a container escape. This is expected behavior. That is what makes it important. The container did not need a vulnerability. It did not need malware. It only needed permission that the operator gave it. Dangerous mounts include:
```
-v /:/host
-v /etc:/host-etc
-v /home/user:/data
-v /var/run/docker.sock:/var/run/docker.sock
```

A host mount is a deliberate hole in the container boundary. Sometimes it is necessary, especially in development. But it should never be treated as harmless.

## Myth 4: The Docker socket is just another file

The Docker socket is one of the most sensitive files that can be mounted into a container. On many Linux systems, the Docker socket is available at: `/var/run/docker.sock`

This socket is the local API interface to the Docker daemon. Access to it allows a process to ask Docker to create containers, mount filesystems, manage images, and interact with the Docker environment.

OWASP’s Docker Security Cheat Sheet warns that mounting the Docker socket inside a container is equivalent to giving the container unrestricted root access to the host. A safe demonstration is to query Docker version information through the socket:

```bash
sudo docker run --rm \
  -u root \
  -v /var/run/docker.sock:/var/run/docker.sock \
  curlimages/curl \
  --unix-socket /var/run/docker.sock \
  http://localhost/version
```

This command only reads version information, but it proves the container can communicate with the Docker daemon.

The implication is serious: if a container can control Docker, it may be able to ask Docker to start more powerful containers. The container boundary can collapse because the attacker no longer needs to directly break out. They can use the daemon as the control plane. This is why `/var/run/docker.sock` should be treated as a high-risk mount, not a convenience feature.

## Myth 5: `--privileged` just fixes annoying errors

The `--privileged` flag is often used as a shortcut when something inside a container does not work. It may fix the immediate problem, but it does so by removing many of the protections that made the container safer in the first place. OWASP recommends avoiding privileged containers and granting only the specific Linux capabilities required by the workload. It also notes that `--privileged` adds all Linux kernel capabilities to the container.

- Compare a normal container: `sudo docker run --rm alpine sh -c 'id; ls /dev | head; grep CapEff /proc/self/status; grep Seccomp /proc/self/status'`
- With a privileged container: `sudo docker run --rm --privileged alpine sh -c 'id; ls /dev | head; grep CapEff /proc/self/status; grep Seccomp /proc/self/status'`

The privileged container has a much broader permission set and can see more of the system’s device interface. The flag also disables the Seccomp filters.

The exact capabilities depend on the application. The important rule is that permission should be intentional and minimal. If a service only runs with `--privileged`, that is not a small configuration detail. It is a major security design problem.

## Myth 6: If the image runs, the image is fine

A container image is not only application code. It contains a filesystem, dependencies, package manager artifacts, metadata, build layers, and sometimes secrets. This makes images part of the software supply chain.

One common mistake is putting secrets into Docker build arguments or environment variables. Docker explicitly warns that sensitive data should not be used in `ARG` or `ENV` instructions because they can persist in the final image.

Create a deliberately bad Dockerfile:
```Dockerfile
FROM alpine
ARG API_TOKEN
RUN echo "Using token: $API_TOKEN" > /tmp/build.log
RUN rm /tmp/build.log
CMD ["sh"]
```

Build it:
```bash
sudo docker build --build-arg API_TOKEN=demo-secret-123 -t secret-demo .
```

Inspect the image history:
```bash
sudo docker history --no-trunc secret-demo
```

The point is not that this exact example is how every secret leaks. The point is that images have memory. Build steps, layers, metadata, and copied files can preserve information longer than expected. If a secret enters an image, assume it may be recoverable.

## Myth 7: Popular images are automatically trustworthy

Public container registries are convenient, but every image pull is a trust decision.

A popular image may still contain vulnerable dependencies. A familiar project may still have a compromised release. A security tool may still be delivered through a compromised pipeline.

[In 2025, Binarly reported](https://www.binarly.io/blog/persistent-risk-xz-utils-backdoor-still-lurking-in-docker-images) that artifacts related to the XZ Utils backdoor were still present in some Docker Hub images more than a year after the original XZ supply-chain incident. Their analysis focused on Debian images, and they noted that the impact on images from other affected distributions remained unknown.

This example matters because it shows how container images can preserve old supply-chain problems. Even after a vulnerability becomes public, images built during a compromise window may remain available or may have been used as bases for other images.

A more recent example is the 2026 Trivy supply-chain compromise. [Docker reported that on March 19, 2026](https://www.docker.com/blog/trivy-supply-chain-compromise-what-docker-hub-users-should-know/), threat actors compromised Aqua Security’s CI/CD pipeline and used stolen credentials to push backdoored versions of the aquasec/trivy vulnerability scanner image to Docker Hub. The malicious images contained an infostealer targeting CI/CD secrets, cloud credentials, SSH keys, and Docker configurations. A second wave followed on March 22.

This is an uncomfortable example because Trivy is a security scanner. The implication is clear: security tools are also software dependencies, and they can also become part of the attack path. Image trust is not a one-time decision. It is an ongoing process.

## Myth 8: Container escapes are only theoretical

Many container compromises do not require a real escape because the container is misconfigured. However, real runtime escape vulnerabilities do happen. In 2024, several [vulnerabilities affecting runc and BuildKit were disclosed](https://www.wiz.io/blog/leaky-vessels-container-escape-vulnerabilities) and widely discussed under the name “Leaky Vessels.” Wiz described CVE-2024-21626 as a runc vulnerability that could allow container escape under multiple conditions by exploiting leaked file descriptors to access the host filesystem.

[Red Hat’s advisory for CVE-2024-21626](https://access.redhat.com/security/vulnerabilities/RHSB-2024-001) describes a file descriptor leak and path traversal issue involving WORKDIR and RUN handling, with related BuildKit vulnerabilities also referenced. This matters because runc and BuildKit are not obscure components. They are part of the basic container ecosystem. If this layer is vulnerable, the isolation model itself may be weakened.

Another example is [Docker Desktop CVE-2025-9074](https://docs.docker.com/security/security-announcements/). Docker’s security announcement states that a malicious container running on Docker Desktop could access the Docker Engine and launch additional containers without requiring the Docker socket to be mounted. Docker also stated that this could allow unauthorized access to user files on the host system, and that Enhanced Container Isolation did not mitigate the vulnerability.

That case is especially important because it breaks a common assumption:

> I did not mount the Docker socket, so this class of problem cannot happen.

For CVE-2025-9074, the Docker socket did not need to be mounted.

Container escape risk can come from several places:
- *Misconfiguration*: The container is given too much access.
- *Runtime vulnerability*: A bug in Docker, runc, BuildKit, containerd, or related tooling weakens the boundary.
- *Kernel vulnerability*: A kernel bug is reachable from inside the container.
- *Supply-chain compromise*: The image, base image, scanner, or build system is already malicious.
 
## Myth 9: Containers Reduce Complexity

Containers often feel like they reduce complexity because they make applications easier to package, move, and start. Instead of installing a runtime, system packages, libraries, and services directly on a host, we can place them into an image and run the application with a single command. This is a real benefit: NIST describes containers as a portable, reusable, and automatable way to package and run applications. But this does not mean the complexity disappears. It usually moves into Dockerfiles, image layers, registries, Compose files, volumes, networks, runtime flags, secrets, and CI/CD pipelines.

A simple command such as `docker compose up` can hide a lot of infrastructure. Docker Compose is specifically designed to define application services, networks, volumes, and related configuration in a Compose file. That is convenient, but it also means the application is no longer just “the code.” It is now the code plus image build rules, service dependencies, internal DNS, persistent storage, exposed ports, environment variables, and registry trust. Docker’s Compose documentation describes this model around services, networks, and volumes, which are all operational and security-relevant parts of the system.

This becomes important for security because every new layer creates new assumptions. A Dockerfile may silently depend on an outdated base image. A Compose file may expose a port that was only meant for development. A named volume may preserve sensitive data after the container is removed. An environment variable may contain a password. A registry tag such as latest may change without warning. The container made the application easier to start, but the security model now depends on understanding the image, the build process, the registry, the runtime configuration, and the host.

Containers can also make complexity more visible. A Dockerfile documents how the image is built. A Compose file documents how services connect. Multi-stage builds can separate build-time dependencies from the final runtime image, producing cleaner and smaller images, but they also introduce more build stages and more decisions about what should or should not be copied into the final image. Docker recommends multi-stage builds to improve builds and reduce final image size, which is useful, but it is still another layer that must be understood and maintained.

The security implication is that containers **do not automatically simplify the system; they reorganize it**. OWASP notes that Docker can **improve security when used correctly**, but **misconfigurations can reduce security or introduce new vulnerabilities**. This is the key reality behind the myth: containers reduce some operational friction, but they introduce new places where mistakes can happen. A containerized application is only simpler if the team understands and controls the image, runtime permissions, secrets, volumes, networks, and update process.

A better way to say it is: **containers do not reduce complexity; they make complexity portable.** That portability is powerful, but it also means mistakes become portable too. A bad Dockerfile, weak Compose configuration, leaked secret, vulnerable base image, or dangerous runtime flag can be copied across laptops, CI systems, test servers, and production environments. Containers are not a shortcut around architecture and security; they are a new layer of architecture and security that must be designed deliberately.
