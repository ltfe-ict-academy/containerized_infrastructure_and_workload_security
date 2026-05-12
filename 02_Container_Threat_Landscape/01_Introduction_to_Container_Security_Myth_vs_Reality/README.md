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

https://chatgpt.com/c/6a031ba2-df14-832e-a3c3-4ce09983ee18

## Myth 8: Container escapes are only theoretical



8. Myth 7: “Official or popular images are always safe”
Explanation

Popularity is not the same as trust. Official images, verified publishers, signed artifacts, SBOMs, digest pinning, vulnerability scanning, and controlled registries all reduce risk, but none of them create perfect safety.

This is especially important because container images are often rebuilt from other images. A compromised base image can silently affect many downstream images.

Real example: XZ Utils backdoor still found in Docker images

The XZ Utils backdoor was one of the most important open-source supply-chain incidents of 2024. In 2025, Binarly reported that XZ backdoor artifacts were still present in some Docker images. Binarly focused on Debian-based images and noted that the impact on images from other affected distributions was unknown.

This is a strong teaching example because it shows that even after a major incident becomes public, vulnerable or malicious artifacts can remain in container ecosystems.

Suggested instructor wording:

“The incident was discovered, explained, and widely discussed. But container images built during the bad window can still exist. Containers make software portable, but they also make old mistakes portable.”

Real example: Trivy Docker Hub supply-chain compromise

In March 2026, Docker published a post about a Trivy supply-chain compromise in which attackers compromised Aqua Security’s CI/CD pipeline and pushed backdoored versions of the aquasec/trivy vulnerability scanner image to Docker Hub. Docker stated that the malicious images contained an infostealer targeting CI/CD secrets, cloud credentials, SSH keys, and Docker configurations.

This is especially powerful for students because Trivy is itself a security tool. The lesson is not “do not use scanners.” The lesson is:

“Security tools are also software supply chain dependencies.”

Teaching point

A mature container image policy should include:

Use trusted base images.
Pin by digest, not only by tag.
Scan images before use.
Rebuild images regularly.
Avoid stale base images.
Use private registries for approved images.
Do not blindly trust public image names.
Monitor for compromised upstreams.
9. Myth 8: “Container escapes are only conference talks”
Explanation

Container escapes are real, but they are not the only risk. In many incidents, attackers do not need a sophisticated escape because the container is already misconfigured. However, runtime vulnerabilities do happen, and learners should know that the boundary depends on complex software.

Real example: Leaky Vessels, 2024

In early 2024, multiple vulnerabilities were disclosed in runc and BuildKit. These were collectively discussed as “Leaky Vessels.” Wiz described the vulnerabilities as affecting runc and BuildKit and posing a container escape risk. Snyk also described four container breakout vulnerabilities in core container infrastructure that could allow unauthorized access to the underlying host from within a container.

One of the best-known issues was CVE-2024-21626 in runc. Red Hat described it as a flaw involving WORKDIR handling, a file descriptor leak, and potential container breakout or host compromise.

Use this as a bridge between configuration mistakes and real vulnerabilities:

“Most of today’s demos are misconfigurations. But even if you avoid those mistakes, you still depend on the correctness of the runtime, builder, kernel, and security profiles.”

Real example: Docker Desktop CVE-2025-9074

Docker’s own security advisory says Docker Desktop 4.44.3 fixed CVE-2025-9074, where a malicious container running on Docker Desktop could access the Docker Engine and launch additional containers without requiring the Docker socket to be mounted. Docker also stated this could allow unauthorized access to user files on the host system, and that Enhanced Container Isolation did not mitigate the vulnerability.

This example is useful because it challenges a common assumption:

“I did not mount the Docker socket, so I am safe.”

For this vulnerability, the socket did not need to be mounted. That makes it a good “myth vs. reality” story.

Teaching point

Container escape risk has three layers:

Misconfiguration escape:
The operator gives the container too much access.

Runtime escape:
A bug in runc, BuildKit, Docker Desktop, containerd, or related components weakens isolation.

Kernel escape:
A kernel vulnerability is reachable from inside the container.









### Inference From The Advisory Pattern

This is an inference from the official advisory history:

the problem is not one isolated bug.

The problem is that container isolation depends on a complex interaction between:

- kernel features
- mount logic
- file descriptor handling
- procfs behavior
- LSM integration
- runtime correctness

That is not a reason to panic.

It is a reason to stop talking about containers like a solved isolation primitive.

## Myth 5: "The Docker Daemon Is Just Plumbing"

This is one of the most damaging misunderstandings in real environments.

### Reality

Docker's own documentation still warns that opening the Docker daemon to remote clients can leave you vulnerable to unauthorized host access and other attacks. As of **April 9, 2026**, the documentation explicitly warns that if the connection is not properly secured, remote non-root users can gain root access on the host.

The daemon is not a convenience helper.

It is a high-value control plane.

If an attacker can talk to it, they can often:

- start new containers
- mount host files
- enter running containers
- extract images
- create privileged workloads

## Real-World Example: TeamTNT And Exposed Docker Management Surfaces

On **September 8, 2020**, Microsoft published a case study describing TeamTNT activity targeting:

- exposed Docker API servers
- exposed Weave Scope instances without authentication

The Microsoft write-up described attackers deploying malicious images, running cryptocurrency miners, and spreading through exposed Docker endpoints. It also described Weave Scope as especially dangerous because it could provide shell access to pods or nodes as root when exposed without authentication.

This is exactly the type of operational failure this module is meant to highlight:

- no fancy exploit chain
- no nation-state magic
- just exposed management surfaces and terrible assumptions

## Myth 6: "Containers Reduce Complexity"

Operationally, containers often reduce some kinds of drift and packaging pain.

Security-wise, they usually add layers you now need to defend:

- the image
- the registry
- the build system
- the runtime
- the daemon
- the orchestration layer
- the network overlay
- the secrets path
- the monitoring and logging plane

This is why saying "we containerized it" tells a security engineer almost nothing.

The follow-up questions are what matter:

- what image?
- from where?
- built by whom?
- running as which user?
- with which mounts?
- with which capabilities?
- exposed through which ports?
- reachable from which networks?
- controlled through which daemon or orchestrator APIs?
