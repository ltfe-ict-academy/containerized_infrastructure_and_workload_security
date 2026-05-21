# Container Hardening Strategies

Container hardening is not one setting. It is a collection of choices that reduce privilege, reachability and writable surface. Good hardening does not make exploitation impossible. It makes post-exploitation slower, noisier, and less damaging. In other words, container hardening is mostly the art of saying **no** to unnecessary power.

Common mistakes show up constantly:
- running everything as root because it is easier
- using `--privileged` to make problems go away
- mounting Docker socket into app or CI containers
- leaving shells and package managers in production images without a reason
- disabling default seccomp or AppArmor profiles
- forgetting resource limits
- mounting large parts of the host filesystem
- publishing ports widely and calling the environment "hardened"

## Keep the host OS, kernel, Docker Engine, Docker Compose, and container runtime updated

Containers are not virtual machines; they **share the host kernel**. That means an outdated host kernel, Docker Engine, containerd, runc, or Docker Compose can become a direct path from “compromised container” to “compromised host.” This is why OWASP lists “Keep Host and Docker up to date” as Rule #0 in its Docker Security Cheat Sheet. A vulnerable application inside a container is bad, but a vulnerable container runtime is worse because the **runtime is the software enforcing the isolation boundary**. If that boundary has a known flaw, an attacker may be able to escape the container, read or modify host files, abuse the Docker API, cause denial of service, or gain higher privileges on the underlying system.

A practical example is the historical `runc` container escape vulnerability **CVE-2019-5736**. runc is one of the low-level tools used to start containers. In affected versions, an attacker who controlled a malicious container image, or who already had write access inside a container and could trigger docker exec, could overwrite the host runc binary and potentially gain root-level execution on the host. This is a perfect classroom example because it shows why “the app is inside a container” is not enough: if the runtime itself is vulnerable, the container boundary can fail.

A newer example is **CVE-2024-21626**, another runc issue affecting Docker, Kubernetes, and other container platforms. CERT-EU described it as a high-severity vulnerability that could allow attackers to escape containers and gain unauthorized access to the host operating system. Red Hat also noted that exploitation could involve tricking a user into building or running a malicious image, or executing a malicious process inside a container with runc exec.

The risk is not limited to container escape. Runtime and engine bugs can also produce denial-of-service conditions. For example, Ubuntu’s security advisory for containerd described vulnerabilities where an attacker could potentially cause denial of service, including through improper handling of goroutines during container attach operations. This matters because a single untrusted workload may be able to affect the stability of the whole Docker host if the runtime has a known resource-exhaustion bug.

In practice, hardening means treating the Docker host like production infrastructure, not like a disposable developer tool. Administrators should patch the operating system, kernel, Docker Engine, Docker CLI, Docker Compose plugin, containerd, and runc as part of a regular maintenance process. They should also subscribe to [Docker security announcements](https://docs.docker.com/security/security-announcements/), because Docker publishes security updates and CVE notices for Docker components.

Example verification commands:

```bash
# Check host OS and kernel
cat /etc/os-release
uname -a

# Check Docker client and server versions
sudo docker version

# Check Docker Compose version
sudo docker compose version

# Check runtime versions
sudo docker info | grep -i runtime
sudo containerd --version
sudo runc --version
```

Example update commands on Debian/Ubuntu-style systems:
```bash
# If Docker was installed from Docker's official repository:
sudo apt update
sudo apt upgrade
```

A container breakout is rarely caused by “Docker being insecure by default”; more often, it happens when a vulnerable runtime, weak configuration, excessive privileges, or an outdated host gives the attacker a path out. Keeping the host and Docker stack updated removes many known escape and denial-of-service paths before attackers can use them.

## Do not expose the Docker daemon over unauthenticated TCP

The Docker daemon is one of the most sensitive services on a Docker host because it controls image builds, container creation, volume mounts, networking, and access to host resources. By default, Docker listens on a local Unix socket, usually `/var/run/docker.sock`. Exposing the daemon over TCP, especially with something like `tcp://0.0.0.0:2375`, turns the Docker API into a network-accessible control plane. If that TCP listener is unauthenticated and reachable, anyone who can connect to it can effectively control Docker on that host. OWASP explicitly warns that enabling the TCP Docker daemon socket can expose unauthenticated and unencrypted direct access to the Docker daemon. Docker’s own documentation recommends protecting daemon access and using SSH or TLS when remote access is needed.

The practical risk is host compromise. An attacker does not need a kernel exploit or sophisticated container escape if they can talk directly to the Docker API. They can simply create a new container, mount the host filesystem into it, and access or modify host files. For example, if an attacker can run Docker API commands remotely, they may start a privileged container or mount `/` from the host into `/host` inside the container. From there, they could read secrets, modify SSH keys, alter system files, steal application data, or install persistence. This is why access to the Docker daemon is commonly treated as equivalent to root access on the host. OWASP makes the same point for Docker socket access: giving access to the Docker socket is effectively giving unrestricted root access to the host.

A vulnerable configuration often looks like this:
```bash
dockerd -H unix:///var/run/docker.sock -H tcp://0.0.0.0:2375

# The dangerous part is: -H tcp://0.0.0.0:2375
```

This means Docker is listening on all network interfaces, commonly without TLS. Port 2375 is the conventional plaintext Docker API port. If this is reachable from another machine, the attacker can point their Docker client at it.

**Example** (do this example only in a safe lab environment, never in a public or production network):
```bash
# On the vulnerable host run
sudo systemctl edit docker.service

# Paste the following into the editor
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375

# Apply and Restart
sudo systemctl daemon-reload
sudo systemctl restart docker

# Run this command to see if Docker is now listening on that port:
sudo ss -tulpn | grep 2375

# From another machine, try to connect to the Docker API:
sudo docker -H <victim_ip>:2375 ps

# If that works, the attacker can likely create containers too:
docker -H tcp://<victim_ip>:2375 run --rm -it -v /:/host alpine sh

# Inside that container, the attacker can inspect the host filesystem:
ls /host
cat /host/etc/passwd
ls /host/etc/hosts

# Remove the vulnerable configuration after testing and restart Docker:
sudo rm /etc/systemd/system/docker.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl restart docker

# Check no longer listening on TCP:
sudo ss -tulpn | grep 2375
```

You can check for this with the following commands:
```bash
sudo ss -tulpn | grep 2375
docker info
ps aux | grep dockerd
systemctl cat docker
cat /etc/docker/daemon.json
```

If remote administration is required, [prefer SSH-based Docker contexts](https://docs.docker.com/engine/security/protect-access/#use-ssh-to-protect-the-docker-daemon-socket) instead of opening the daemon directly. This is usually better because SSH gives you mature authentication, logging, key management, bastion-host support, and network restrictions without exposing the Docker API directly.

The Docker daemon is not just another API; it is the control interface for the host’s container system. If it is exposed without authentication, the attacker effectively gets a remote root-like management interface. The secure default is Unix socket only. If remote access is needed, use SSH-based Docker contexts. If TCP is unavoidable, use mutual TLS, firewall restrictions, monitoring, and never expose plaintext unauthenticated 2375 to a network.

## Do not mount `/var/run/docker.sock` into application containers

Mounting `/var/run/docker.sock` into a container gives that container access to the Docker daemon API on the host. This is extremely dangerous because the Docker daemon controls container creation, volume mounting, networking, images, and many host-level operations. OWASP’s Docker Security Cheat Sheet is very direct about this: the Docker socket is the primary entry point for the Docker API, it is owned by root, and giving access to it is equivalent to giving unrestricted root access to the host.

The risky pattern usually appears in Compose like this:
```yaml
services:
  app:
    image: myapp:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
```

A common mistake is thinking this is safe if the socket is mounted read-only:
```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
```

This is misleading. The `:ro` flag applies to the socket file mount itself, but Unix socket communication is still possible. The container may still be able to send Docker API requests through the socket. So `:ro` does not turn Docker API access into safe read-only access.

This issue often appears in CI/CD runners, reverse proxies, auto-updaters, monitoring agents, and “Docker management UI” containers. These tools sometimes need to discover containers or launch builds, so teams mount the socket as a shortcut. The problem is that if one of those tools has a web vulnerability, bad plugin, weak admin password, SSRF bug, command injection bug, or exposed dashboard, the attacker may inherit Docker host control.

For CI/CD image building, use alternatives that do not require the host Docker socket where possible, such as rootless BuildKit, Kaniko, Buildah, Podman, remote builders, or a dedicated isolated build host. The exact choice depends on the environment, but the design principle is the same: build jobs should not receive direct control over the production Docker daemon.

For tools that only need container metadata, prefer a restricted proxy in front of the Docker socket rather than exposing the raw socket. For example, a [Docker socket proxy](https://github.com/tecnativa/docker-socket-proxy) can restrict allowed API endpoints so a monitoring tool can list containers but cannot create privileged containers or mount host paths. This is still a sensitive component and must be carefully configured, but it is safer than raw socket exposure.

For the example run: `sudo docker run -v /var/run/docker.sock:/var/run/docker.sock --name=myapp alpine`

You can audit for socket mounts with:
```bash
sudo docker ps --format '{{.Names}}' | while read name; do
  echo "== $name =="
  sudo docker inspect "$name" \
    --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' \
    | grep docker.sock || true
done
```

You can also search Compose files:
```bash
grep -R "docker.sock" .
```

Mounting `/var/run/docker.sock` into a container gives the container the ability to control Docker on the host. If that container is compromised, the attacker can often create a new container with the host filesystem mounted and take over the host. Avoid this pattern for application containers. Use isolated build systems, rootless builders, dedicated build hosts, or tightly restricted socket proxies only when there is a clear operational need.

## Restrict membership of the docker group; access to Docker is effectively privileged host access

On Linux, users normally need root privileges to interact with the Docker daemon through `/var/run/docker.sock`. To make Docker easier to use, [many installations allow users to run Docker without sudo](https://docs.docker.com/engine/install/linux-postinstall/#manage-docker-as-a-non-root-user) by adding them to the docker group. This is convenient, but it is also a major security decision. Docker’s own documentation warns that the docker group grants root-level privileges to the user. In other words, being in the docker group should be treated almost the same as being allowed to run unrestricted sudo.

The reason is simple: the Docker daemon usually runs as root, and members of the docker group can send commands to that daemon. A user in the docker group can create containers, mount host directories, change container networking, access volumes, inspect secrets accidentally placed in containers, and run images with dangerous options. Even if the user does not have sudo, Docker can become a path to host-level access. Docker’s security documentation explains that the Docker daemon attack surface must be protected because only trusted users should be allowed to control it.

A practical exploitation example:

1. Prerequisite: the attacker has a user account on the host and is a member of the docker group.
```bash
sudo usermod -aG docker $USER
newgrp docker
id
```

2. That user can start a container and mount the host filesystem:
```bash
docker run --rm -it -v /:/host ubuntu bash
```

3. If the container is running as root inside the container, file writes to the mounted host filesystem may also be possible depending on host protections, filesystem permissions, user namespaces, and mount options. A common privilege-escalation demonstration is creating a setuid shell on the host:
```bash
cp /bin/bash /host/tmp/rootbash
chown root:root /host/tmp/rootbash
chmod 4755 /host/tmp/rootbash
exit
```
4. Now the attacker can run `/tmp/rootbash` on the host and get a root shell:
```bash
/tmp/rootbash -p
id
```

This shows why docker group access is not a harmless convenience. The user did not need the root password. They abused Docker’s normal volume-mounting feature to interact with the host filesystem through a root-controlled daemon. A common insecure operational pattern is adding every developer, operator, CI account, or automation account to the docker group. This increases the blast radius. If any one of those accounts is phished, compromised through SSH keys, reused passwords, stolen CI tokens, or malware, the attacker may gain Docker daemon control and then host-level control.

A better approach is to keep docker group membership very small and intentional: `getent group docker`

Remove users who do not strictly need Docker access:
```bash
sudo gpasswd -d $USER docker
newgrp docker
```

If developers need Docker on their laptops, that is a different risk model from production. On a developer workstation, being in the docker group may be acceptable if the user already owns the machine. On a shared server, jump host, CI runner, lab machine, or production system, it is much more dangerous because one user’s Docker access can become everyone’s host compromise.

Membership in the docker group is not just “permission to run containers.” It is permission to control a root-owned daemon that can mount host filesystems and start powerful containers. Restrict the group to trusted administrators only, audit it regularly, remove stale users, avoid adding CI or application accounts casually, and treat Docker group membership with the same seriousness as unrestricted sudo.


## Strengthening Container Isolation with Seccomp

Containers are Linux processes that share the host kernel. Namespaces limit what a container can see, cgroups limit what it can consume, and capabilities limit some privileged actions. Seccomp adds another layer by limiting what system calls a containerized process can make to the kernel.

**A system call is the interface between an application and the kernel.** When a process wants to open a file, create another process, change permissions, mount a filesystem, or interact with networking, it usually asks the kernel through a syscall.

**Seccomp, short for secure computing mode**, restricts which syscalls a process is allowed to use. For containers, this is useful because **many kernel operations should not be available to ordinary application workloads**.

For example, a normal web application container usually has no reason to:
- change the host clock;
- load or unload kernel modules;
- reboot the host;
- mount filesystems;
- interact with the kernel keyring;
- trace other processes;
- create new namespaces from inside the container.

Blocking these syscalls reduces the attack surface exposed to a compromised container.

A compromised container is already running code on the host kernel, just inside a restricted environment. Seccomp makes that environment narrower. It cannot fix a vulnerable application, and it does not make containers equal to virtual machines, but it can prevent the attacker from using kernel features the application never needed.

Docker [enables a default seccomp profile](https://github.com/moby/profiles/blob/main/seccomp/default.json) for normal containers. This profile blocks many syscalls that are dangerous or rarely needed in application containers, while still allowing most workloads to run normally. [Docker describes](https://docs.docker.com/engine/security/seccomp) this as a default profile intended to provide broad compatibility while reducing kernel attack surface.

### Hands-On: Using Seccomp in Docker

Run a normal container and inspect its seccomp status:
```bash
sudo docker run --rm alpine sh -c 'grep Seccomp /proc/self/status'

# Example output:
# Seccomp:        2
# Seccomp_filters:        1
```

`Seccomp: 2` means the process is running in seccomp filter mode. This confirms that a seccomp profile is active.

The `unshare` command can create new namespaces. A normal application container should not usually create additional namespaces from inside the container.

```bash
sudo docker run --rm debian:bookworm-slim unshare --map-root-user --user sh -c 'whoami'

# Example output:
# unshare: unshare failed: Operation not permitted
```

The container did not fail because Debian is broken. The syscall was blocked by Docker’s default seccomp profile.

Now disable seccomp and try again:
```bash
sudo docker run --rm \
  --security-opt seccomp=unconfined \
  debian:bookworm-slim \
  unshare --map-root-user --user sh -c 'whoami'
```

This demonstrates the value of the default profile. With seccomp enabled, the syscall is denied. With seccomp disabled, the container can perform an operation that should usually not be available to application workloads.

Docker lets you provide a custom profile:
```bash
sudo docker run --rm \
  --security-opt seccomp=/path/to/profile.json \
  alpine sh
```

For most containers, keep Docker’s default seccomp profile enabled. It provides a good balance between compatibility and security.

Custom profiles can be useful for sensitive workloads, but they require testing and maintenance. Application developers usually do not call syscalls directly; language runtimes, libraries, and base images do that underneath the application. After an image, runtime, or kernel upgrade, the set of syscalls used by the workload may change. Very strict profiles can therefore break applications unexpectedly

Use this approach:
1. Start with Docker’s default seccomp profile.
2. Avoid seccomp=unconfined.
3. Investigate blocked syscalls instead of disabling the whole profile.
4. Use custom profiles only where the security benefit justifies the maintenance.
5. Test profiles before applying them to important workloads.


## Strengthening Container Isolation with AppArmor

[AppArmor](https://gitlab.com/apparmor) works at a different layer: it limits what a process is allowed to do with files, capabilities, networking, mounts, and other system resources.

AppArmor, short for Application Armor, is a Linux Security Module. [Docker’s documentation describes](https://docs.docker.com/engine/security/apparmor/) it as a Linux security module where an administrator associates a security profile with a program, and Docker expects an AppArmor policy to be loaded and enforced on systems that use it.

AppArmor profiles describe what a program is allowed to do. For containers, this usually means controlling behavior such as:
- reading or writing specific filesystem paths;
- using Linux capabilities;
- mounting filesystems;
- accessing sensitive `/proc` or `/sys` locations;
- using tracing or debugging behavior such as `ptrace`;
- performing certain network actions.

The important difference from normal Linux file permissions is that AppArmor is a mandatory access control system. Normal Linux permissions are discretionary: if a user owns a file, they may be able to grant access to someone else. **AppArmor policy is enforced by the system and cannot be bypassed just because the process runs as root inside the container.** AppArmor as one of the Linux Security Modules used to strengthen container isolation, alongside seccomp and SELinux.

On systems with AppArmor enabled, [Docker automatically creates](https://github.com/moby/profiles/blob/main/apparmor/template.go) and loads a default profile called `docker-default`. Docker generates this profile in `tmpfs` and loads it into the kernel. This profile applies to containers, not to the Docker daemon itself.

The `docker-default` profile is designed to be moderately protective while still allowing most containers to work normally. Docker applies it unless you override it with `--security-opt`. This is why AppArmor is often invisible during normal Docker use. You may not have written a profile yourself, but Docker may already be applying one.


### Hands-On: Using AppArmor in Docker

On a Linux Docker host, check whether AppArmor is active:
```bash
sudo aa-status
# Look for "apparmor module is loaded" and "profiles are in enforce mode"
```

You can also check the enabled Linux Security Modules:
```bash
cat /sys/kernel/security/lsm
# Look for "apparmor" in the output
```

See the Profile Applied to a Container:
```bash
# Start a simple container:
sudo docker run -d --name apparmor-demo alpine sleep 300

# Inspect the AppArmor profile:
sudo docker inspect apparmor-demo --format '{{.AppArmorProfile}}'

# This confirms that Docker applied its default AppArmor profile to the container.

# Clean up:
sudo docker rm -f apparmor-demo
```

For comparison, run a container without AppArmor confinement:
```bash
sudo docker run --rm \
  --security-opt apparmor=unconfined \
  alpine sh -c 'cat /proc/self/attr/current'
```

This should be avoided in production unless there is a clear, reviewed reason. Disabling AppArmor removes one of the kernel-level restrictions around the container.

The following profile is intentionally simple for demonstration purposes. It allows broad container behavior but denies writing under `/tmp/demo-protected/`. This gives us an easy way to see AppArmor block an operation.

Create the profile:
```bash
sudo mkdir -p /etc/apparmor.d/containers

sudo tee /etc/apparmor.d/containers/docker-deny-demo-tmp > /dev/null <<'EOF'
#include <tunables/global>

profile docker-deny-demo-tmp flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  file,
  network,
  capability,

  deny /tmp/demo-protected/** wklx,
}
EOF

# Load the profile into the kernel:
sudo apparmor_parser -r -W /etc/apparmor.d/containers/docker-deny-demo-tmp

# Run the container with --security-opt apparmor=<profile-name>
sudo docker run --rm \
  --security-opt apparmor=docker-deny-demo-tmp \
  alpine sh -c '
    mkdir -p /tmp/demo-protected
    echo test > /tmp/allowed-file
    echo test > /tmp/demo-protected/blocked-file
  '
```

The container can still run and write elsewhere, but AppArmor blocks the path protected by the profile.

`aa-status` can be used to check loaded profiles and whether they are in enforce or complain mode. In enforce mode, AppArmor actively blocks actions outside the profile; in complain mode, it logs violations without blocking them.

For most Docker workloads, keep the default `docker-default` AppArmor profile enabled. Do not use `apparmor=unconfined` as a quick workaround.

Custom profiles are useful when a workload is sensitive or has predictable behavior, but they require testing. A profile that is too strict can break the application. A profile that is too broad may provide little extra protection. In practice, start with Docker’s default profile, investigate denied actions carefully, and create custom profiles only where the security benefit justifies the maintenance.

## Strengthening Container Isolation with SELinux

SELinux, or Security-Enhanced Linux, is another Linux Security Module used to strengthen process isolation. Like AppArmor, it implements mandatory access control, but it works in a different way. AppArmor is commonly described as path-based, while SELinux is label-based.

SELinux is especially common on Red Hat-based distributions such as RHEL, Fedora, and CentOS Stream. In container environments, it is tightly integrated with Red Hat-maintained runtimes such as Podman and CRI-O.

[SELinux controls](https://opensource.com/business/13/11/selinux-policy-guide) what a process can do based on labels. A process runs in an SELinux domain, and files are assigned SELinux types. Policy rules then decide whether a process in one domain can read, write, execute, or otherwise interact with an object of a specific type.


Containers share the host kernel, and a container process is still a Linux process on the host. SELinux adds another layer of control around that process.

For example, SELinux can help restrict:
- which host files a container can access;
- whether one container can access another container’s files;
- which mounted volumes are usable by a container;
- how container processes interact with other labeled system resources.

This is especially valuable when containers use bind mounts. A bind mount deliberately exposes a host directory inside a container. SELinux can prevent the container from using that directory unless the directory has a label that container policy allows.

Keep SELinux enforcing on platforms where it is part of the host security design. On Red Hat-based container hosts, SELinux is one of the strongest default protections around container file access.

## Other tips for strengthening container isolation
- Isolate containers with a user namespace: https://docs.docker.com/engine/security/userns-remap
- gVisor
- Kata Containers
- Lightweight/Micro Virtual Machines
- Unikernels


## Consider Docker rootless mode

Running a container as a non-root user is good practice, but it is not the same thing as running the container engine in rootless mode.

This distinction matters. In a normal Docker installation, the Docker daemon runs as root. Even when a container process is configured with `USER appuser` or started with `docker run --user`, the daemon that creates the container, prepares mounts, configures networking, and talks to the runtime may still be a root-owned host service. Docker’s own security documentation warns that the Docker daemon normally requires root privileges unless rootless mode is used, and that only trusted users should control the daemon because Docker can create containers with host filesystem access.

Rootless mode changes that model. **Docker rootless mode runs both the Docker daemon and containers as a non-root user**, using a user namespace so that privileged-looking operations inside the container are mapped to an unprivileged identity on the host. Docker describes rootless mode as a way to mitigate potential vulnerabilities in the daemon and runtime, and explicitly distinguishes it from `userns-remap`, where the daemon itself still runs with root privileges.

The goal is not to make containers magically safe. The goal is to reduce the blast radius. If a container escape or daemon vulnerability occurs, the attacker should not automatically land as root on the host.

A rootless container environment allows an unprivileged user to create, run, build, and manage containers without being granted administrative rights on the host. [The Rootless Containers project](https://rootlesscontaine.rs/) defines this as running the container runtime and the containers without root privileges; it also points out several things that are not rootless containers, including giving a user access to `/var/run/docker.sock`, using `docker run --user`, or using Docker `userns-remap` while the daemon remains rootful.

| Configuration                    | What happens                                                                              | Security meaning                                                 |
| -------------------------------- | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `USER appuser` in the Dockerfile | Enforces an explicitly created, named user.   | Good image hardening, but the Docker daemon may still be rootful |
| `docker run --user 10001`        | Forces a hard runtime override using a raw numeric UID.        | Guarantees the process will never run as root, regardless of what the developer did in the Dockerfile.          |
| Docker rootless mode             | The Docker daemon and containers run inside a user namespace as an unprivileged host user | Reduces the impact of daemon or runtime compromise               |


### Why rootless mode matters

In earlier examples, we saw that root inside a container becomes dangerous when the container receives access to host resources: a bind mount, a privileged flag, host networking, extra capabilities, or the Docker socket. Rootless mode does not remove all those risks, but it changes what “root” means from the host’s perspective.

Inside a rootless container, a process may still see itself as UID 0. From inside the container, commands like `id` may show:
```bash
uid=0(root) gid=0(root) groups=0(root)
```

From the host’s perspective, that same process is not real host root. It is mapped through a user namespace to the user who started the rootless engine, or to a subordinate UID/GID range assigned to that user. Docker rootless mode requires `newuidmap` and `newgidmap`, and [Docker recommends](https://docs.docker.com/engine/security/rootless/#prerequisites) at least 65,536 subordinate UIDs and GIDs in `/etc/subuid` and `/etc/subgid` for the user running rootless Docker.

**If the container boundary fails, the attacker should escape into an unprivileged host identity, not directly into host root.**

That is especially valuable on shared systems, developer machines, CI workers, research clusters, and high-performance computing environments where many users may need to run containers but should not receive root-equivalent Docker access.

Capabilities granted inside the container are scoped to the user namespace. A rootless container may appear to have capabilities from inside the container, but those capabilities do not automatically apply to the host namespace. For example, binding to low-numbered ports such as 80 or 443 normally requires privilege on the host. In rootless mode, publishing ports below 1024 requires extra configuration, and Docker recommends using a higher port such as 8080 unless privileged ports are explicitly configured.

Rootless Docker is especially useful when:
- Developers need local Docker functionality without being placed in the docker group.
- CI jobs need to build or run containers without giving the runner host root-equivalent daemon access.
- Multiple users share the same Linux host.
- The workload does not need low-level host networking, privileged ports, host devices, or unsupported Docker features.
- The organization wants to reduce the impact of daemon and runtime compromise.

Known limitations:
- **Storage Drivers**: Only `overlay2` (kernel 5.11+), `fuse-overlayfs` (kernel 4.18+ & installed), `btrfs` (kernel 4.18+ or with user_subvol_rm_allowed), and `vfs` are supported.
- **Resource Management**: cgroup is only supported when using cgroup v2 alongside systemd.
- **Unsupported Features**: AppArmor, Checkpoint, Overlay networks, and exposing SCTP ports are not supported.
- **Network & Port Restrictions**: Special configuration is required to use the ping command.
- **Special Configuration**: Special configuration is required to expose privileged TCP/UDP ports (< 1024).
- **Storage Restriction**: NFS mounts cannot be used as the Docker data-root (a general Docker limitation, not exclusive to rootless mode).

To run Docker deamon in rootless mode [follow the instructions in the Docker documentation](https://docs.docker.com/engine/security/rootless/#prerequisites). Docker rootless mode is useful when teams want Docker compatibility while reducing daemon privilege. Another option is to use [Podman](https://podman.io/).

**Podman is a daemonless, open source, Linux-native tool for finding, running, building, sharing, and deploying OCI containers and images.** The Podman documentation describes its CLI as familiar to Docker users and notes that containers can be run by root or by a non-privileged user.

The important architectural difference is that **Podman does not require a long-running root-owned daemon in the same way Docker traditionally does**. The Podman man page describes Podman as a daemonless container engine and notes that most Podman commands can be run as a regular user without additional privileges.

[Podman Installation Instructions](https://podman.io/docs/installation):
```bash
# For Ubuntu 20.10 and newer
sudo apt-get update
sudo apt-get -y install podman

# Run a quick rootless check without sudo:
podman info | grep -i rootless
```

Let's create and build a demo app:
```bash
# Create a simple Python HTTP server that prints its UID and GID
cat > app.py <<'EOF'
from http.server import BaseHTTPRequestHandler, HTTPServer
import os

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = (
            f"hello from a rootless container\n"
            f"uid={os.getuid()} gid={os.getgid()}\n"
        ).encode()

        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
EOF

# Create a Dockerfile that runs the app as a non-root user
cat > Dockerfile <<'EOF'
FROM python:3.12-alpine

WORKDIR /app
RUN adduser -D -u 10001 appuser
COPY --chown=appuser:appuser app.py /app/app.py
USER appuser
EXPOSE 8080
CMD ["python", "/app/app.py"]
EOF

# Build the image with Podman
podman build -t rootless-podman-demo:v1 .

podman run --rm -d \
  --name rootless-podman-demo \
  -p 8080:8080 \
  rootless-podman-demo:v1

# Check the container is running
podman ps -a

# Check the app is responding
curl http://<SERVER_IP>:8080

# Inspect the container process:
podman exec rootless-podman-demo id
podman top rootless-podman-demo user,pid,comm

# Show the user namespace mapping used by Podman:
podman unshare cat /proc/self/uid_map
podman unshare cat /proc/self/gid_map
```

Podman is often a good fit for developer workstations, Linux servers where daemonless operation is preferred, and environments that want strong rootless workflows by default. Docker rootless mode is often a better fit when the organization already depends heavily on Docker tooling, Docker Compose workflows, or Docker-specific integrations.







## Run containers as a non-root UID/GID

## Don't allow new privileges
- Use security_opt: ["no-new-privileges:true"].

## Don't use the `--privileged` flag

## Set the right capabilities
- Drop all Linux capabilities by default with cap_drop: ["ALL"].
- Add back only the capabilities actually needed, for example NET_BIND_SERVICE if binding to ports below 1024.

## Do not mount sensitive host paths

## Add resource limits to prevent abuse and denial of service





<!-- TO DO HERE https://chatgpt.com/c/69fd9cb9-8fcc-8328-b6aa-fd3734c5c292 -->
- https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md
- https://docs.docker.com/engine/security/rootless/


**User namespaces reduce the danger of container root by mapping it to an unprivileged host identity.** userns-remap improves traditional Docker isolation, rootless Docker improves it further by removing the root daemon from the path, and Podman often makes this model easier because rootless, daemonless containers are central to its design. This does not replace other controls like dropping capabilities, read-only filesystems, seccomp, AppArmor/SELinux, and avoidi



###  Run periodic benchmarks, for example CIS Docker Benchmark or Docker Bench for Security. CIS publishes secure configuration guidance for Docker, and Docker Bench automates many CIS-style checks. 


## Runtime and Docker Compose hardening
 Run containers as a non-root UID/GID with user: "10001:10001" or similar.

 Do not use privileged: true.

 Drop all Linux capabilities by default with cap_drop: ["ALL"].

 Add back only the capabilities actually needed, for example NET_BIND_SERVICE if binding to ports below 1024.

 Use security_opt: ["no-new-privileges:true"].

 Keep Docker’s default seccomp/AppArmor/SELinux protections enabled; do not disable them casually.

 Use read_only: true for the container root filesystem.

 Add explicit writable tmpfs mounts only where the app needs temporary writes, such as /tmp or /run.

 Avoid host bind mounts where possible; prefer named volumes.

 Make bind mounts read-only with :ro unless the container must write.

 Do not mount sensitive host paths like /, /etc, /var/run, /proc, /sys, /dev, or Docker’s data directory.

 Limit resources: memory, CPU, PIDs, file descriptors, and restart loops.

 Use pids_limit, mem_limit, cpus, and ulimits.

 Use init: true to handle zombie processes.

 Use Compose secrets instead of environment variables for passwords, API keys, and certificates. Compose secrets are mounted under /run/secrets/<name> and are granted per service. 

 Segment networks: frontend, backend, database/admin networks as separate networks.

 Use internal: true for networks that should not have external connectivity.

 Publish only required ports.

 Bind host ports to 127.0.0.1 when traffic should only be local or behind a reverse proxy.

 Avoid network_mode: host unless absolutely necessary.

 Avoid pid: host, ipc: host, and uts: host.

 Avoid devices: unless a device is explicitly required.

 Use log limits so a noisy container cannot fill the disk.

 Use health checks and controlled restart policies.

 Do not use latest tags for production.

Docker Compose supports controls such as cap_drop, security_opt, read_only, pids_limit, mem_limit, cpus, tmpfs, user, and network isolation. Compose docs also warn that publishing a port without a host IP binds to all interfaces by default.

## Hardened deployment example



### 1. Image Hardening

By the time a container starts, many hardening choices were already made in the image.

Strong image-level defaults include:

- minimal base images
- only required packages
- no debugging tools unless there is a justified need
- no embedded secrets
- a non-root `USER`
- predictable entrypoints

Why this matters:

- every extra package expands attack surface
- shells, package managers, and admin tools make post-exploitation easier
- root-by-default images train teams into weak runtime habits

Minimal or distroless-style images are not a magic solution, but they do reduce the amount of unnecessary software available to the attacker.

### 2. Run As A Non-Root User

This is one of the simplest and most valuable hardening steps.

If the application does not truly need root inside the container, do not give it root.

Benefits:

- fewer easy privilege abuses inside the container
- less damage from accidental file writes
- stronger alignment with least privilege

This also forces engineering discipline because applications that assume root often reveal other hidden design weaknesses.

### 3. Avoid `--privileged` And Host Namespace Sharing

This should be taught as a bright red warning.

Avoid:

- `--privileged`
- `--pid=host`
- `--network=host` unless truly necessary
- mounting the Docker socket
- broad host-path mounts

These settings often turn a container into "just a process on the host with extra packaging."

When teams use them casually, they are trading away much of the isolation containers were supposed to provide.

### 4. Drop Capabilities Aggressively

Linux capabilities split privileged operations into smaller units.

Docker already drops many capabilities by default, but secure workloads should go further when possible.

Best-practice mindset:

- drop all capabilities you do not need
- ideally `drop all` and add back only what is required

Why it matters:

- many container escapes and abuse paths rely on privilege that is broader than the app actually needs
- extra capabilities can make kernel interaction, network manipulation, or filesystem abuse easier

### 5. Prevent In-Container Privilege Escalation

Use `no-new-privileges`.

This helps stop the process from gaining new privileges through mechanisms such as `setuid` or `setgid`.

That matters because a surprisingly large number of applications carry helper binaries or package leftovers they never meant to expose in a production threat model.

### 6. Use Seccomp, AppArmor, Or SELinux

This is where Linux security modules become very important.

At a practical level:

- **seccomp** reduces the syscall surface
- **AppArmor** or **SELinux** applies mandatory access-control policy

The right teaching point is not:

"memorize every syscall."

It is:

"do not remove these protections casually, and tighten them where the workload permits."

Docker ships a default seccomp profile and supports AppArmor integration.

That means teams already have a baseline they can preserve and improve.

The biggest recurring mistake is not using these controls too little.

It is disabling them because they are "annoying during debugging."

### 7. Make The Root Filesystem Read-Only When Possible

A read-only root filesystem is one of the most useful runtime hardening controls.

Benefits:

- makes persistence harder
- reduces accidental changes to application code and configuration
- blocks many low-effort web-shell and post-exploitation write paths

If the app needs writable space:

- use `tmpfs` for temporary paths
- use narrowly scoped writable volumes
- mount volumes read-only where write access is not needed

This is a very practical control for modern web services.

### 8. Limit Resource Abuse

Resource controls are security controls too.

Why:

- memory exhaustion is a denial-of-service vector
- CPU abuse hurts co-tenants and system stability
- process explosions and file-descriptor exhaustion create noisy incidents

Set limits for:

- memory
- CPU
- process counts where supported
- file descriptors where appropriate
- restart behavior

A hardened service should not be able to crush the whole host just because it was exploited or written badly.

### 9. Control The Network Surface

Networking is part of hardening, not a separate concern.

A runtime with weak privilege settings but overly broad network reach is still dangerous.

Basic network hardening patterns:

- publish only what must be exposed
- bind local-only ports to loopback
- segment services onto the minimum necessary networks
- keep data stores off edge-facing networks
- review egress as well as ingress

This is where Part 03 and Part 04 connect directly.

### 10. Protect The Docker Daemon And Socket

The Docker daemon is a high-value control plane.

If an attacker gets access to it, many other hardening controls become irrelevant.

High-priority rules:

- do not expose the Docker socket to containers
- do not expose the Docker API remotely unless there is a very good reason
- if remote access is necessary, use strong authenticated protection such as SSH or TLS
- keep daemon access tightly restricted

This is one of the most common "convenience shortcuts" that destroys the whole security model.

### 11. Rootless Mode And User Namespace Isolation

Docker supports rootless mode and user-namespace remapping.

These are related but not identical ideas.

High-level difference:

- **rootless mode** runs the daemon and containers as an unprivileged user
- **userns-remap** maps container root to an unprivileged host user range while the daemon itself still runs with elevated privileges

Both can reduce the blast radius of certain host-impacting failures.

The key teaching point is:

if you have not thought about this topic at all, your hardening posture is probably immature.


## A Practical Hardened Service Baseline

For a typical web container, a good baseline often looks like:

```yaml
services:
  api:
    image: my-api:1.0.0
    user: "10001:10001"
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    volumes:
      - type: bind
        source: ./config
        target: /app/config
        read_only: true
```

This is not a universal recipe.

But it is the right direction:

- non-root
- read-only root filesystem
- explicit writable temp path
- dropped capabilities
- privilege escalation blocked
- read-only configuration mount



## How To Prioritize Hardening In Real Life

If a team cannot do everything at once, start with the highest-value controls:

1. stop using `--privileged`
2. stop exposing Docker socket
3. run as non-root
4. drop capabilities
5. use `no-new-privileges`
6. make filesystem read-only where possible
7. segment networks and remove unnecessary published ports
8. patch the host and engine

That sequence gives a lot of value quickly.
