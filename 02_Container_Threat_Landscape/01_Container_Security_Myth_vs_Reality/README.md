# Container Security: Myth vs. Reality

This module exists to break false confidence early.

Many teams talk about containers as if they are a built-in security control:

- "It is in Docker, so it is isolated."
- "It is not a VM, but it is close enough."
- "Root in a container is not real root."
- "If we use official images and keep things patched, we are fine."

That mindset is dangerous.

Containers are an operational and packaging model first. They can be secured well, but they do not become secure by merely existing. In practice they introduce new attack surface, new trust assumptions, and new failure modes. If those assumptions are wrong, the blast radius can be the host, the build system, the registry, or the entire cluster.

This lecture is intentionally sharper than the others. The point is to make participants uncomfortable enough to stop using container language casually.

## Why This Module Matters

This lecture sets the tone for the rest of Part 02 and the rest of the week:

- later in **The Image Problem** we will show that the image itself is a supply-chain artifact with real security consequences
- later in the networking module we will show how easy it is to overexpose services and management surfaces
- later in the hardening module we will show how far you still have to go after "just containerizing" an app

If this module works, participants should stop saying "it runs in a container" as if that answers a security question.

## Learning Objectives

By the end of this module, participants should be able to:

- explain why containers are not equivalent to VMs as a security boundary
- describe the security significance of the Docker daemon, the Docker socket, and the `docker` group
- identify high-risk container misconfigurations that turn isolation into host compromise
- recognize that container escapes are not rare mythology but a recurring vulnerability class
- explain why containers add supply-chain and build-system risk instead of removing it

## Suggested 30-Minute Flow

| Time | Topic |
| --- | --- |
| 0-4 min | Opening shock: what people think containers solve vs what they actually change |
| 4-9 min | Myth 1: containers are basically secure mini-VMs |
| 9-14 min | Myth 2: root in a container is not dangerous |
| 14-19 min | Myth 3: only exotic zero-days matter |
| 19-25 min | Reality check through CVEs and real attacks |
| 25-30 min | Takeaways and bridge into the rest of the course |

## The Core Message

Containers do not magically remove risk.

They shift it:

- from guest OS hardening to shared-kernel risk
- from server patching to image and build-pipeline trust
- from "who can SSH into the box" to "who can talk to the daemon or publish the wrong container"
- from one attack surface to several smaller but more easily multiplied attack surfaces

That trade can be worth it.

But it is still a trade.

## Myth Vs. Reality At A Glance

| Myth | Reality |
| --- | --- |
| Containers are basically small VMs | Linux containers share the host kernel and depend heavily on runtime correctness and configuration hygiene |
| Root in a container is harmless | By default Docker still runs containers as `root`, and the daemon itself runs as `root` unless you deliberately use Rootless mode |
| The daemon socket is just an API | The daemon is effectively a root broker; access to it is often access to the host |
| Only rare container escapes matter | Misconfiguration is more common than zero-days, and zero-days still keep happening |
| Builds and images are packaging details | Builders, frontends, cache mounts, registries, and mutable tags are part of the attack surface |
| Docker defaults make things safe enough | Useful controls exist, but strong isolation and hardening are not what most teams ship by default |

## Myth 1: "Containers Are Basically Secure Mini-VMs"

This is the first dangerous oversimplification.

### Reality

On Linux, containers are not mini-VMs. They are isolated processes sharing the host kernel.

Docker's own security documentation still frames the model around:

- kernel namespaces
- cgroups
- Linux capabilities
- Docker daemon attack surface
- hardening features such as seccomp and AppArmor

That is already a clue: the security story depends on many moving parts, not on one hard boundary.

NIST SP 800-190 has been warning about container-specific security concerns since the final publication on **September 25, 2017**. This is not a new objection invented by skeptics.

### Important Nuance

Participants should understand one important platform detail:

- on Linux servers, containers typically share the host kernel directly
- on Docker Desktop for macOS and Windows, containers run inside a Linux VM, which adds another boundary

That does not make Docker Desktop magically "safe", but it does mean the isolation story is different from a native Linux production host.

### The Teaching Point

If the host kernel or container runtime has a flaw, the security boundary is much weaker than a VM boundary.

That is why container escape vulnerabilities matter so much.

## Myth 2: "Root In A Container Is Not Real Root"

This is only partially true, and teams often turn the partial truth into a fatal mistake.

### Reality

Docker documents two facts that matter a lot:

- the default user inside a container is `root`
- the Docker daemon requires `root` privileges unless you deliberately opt into Rootless mode

Docker also explicitly warns that the `docker` group grants **root-level privileges**.

That means the practical question is not only "is root in the container limited?"

It is also:

- who can start containers?
- who can mount host paths?
- who can talk to the daemon?
- who can use `docker exec`, `docker cp`, `docker run -v /:/host`, or `--privileged`?

In other words, many real-world compromises do not need a kernel 0-day at all.

They need:

- daemon access
- socket access
- bad flags
- bad mounts
- bad trust decisions

## Disposable-VM Demo 1: Docker Socket Equals Host Power

Run this only in an isolated training VM.

The point is simple: if a container can talk to `/var/run/docker.sock`, it can often control the host through the daemon.

Example demonstration:

```bash
docker run --rm -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  docker:28-cli docker ps
```

If that works, the container can ask the daemon to start another container with host mounts:

```bash
docker run --rm -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  docker:28-cli \
  docker run --rm -v /:/host alpine:3.21 chroot /host sh -c "id && hostname"
```

This is not a sophisticated exploit.

It is a configuration mistake.

That is the point.

## Myth 3: "Only Exotic Escapes Matter"

This myth causes teams to overfocus on CVE headlines while ignoring the far more common path: self-inflicted privilege.

### Reality

In many environments, the faster route to host compromise is not a new breakout CVE.

It is one of these:

- `--privileged`
- host PID namespace sharing
- host network namespace sharing
- host filesystem bind mounts
- daemon socket exposure
- remote Docker API exposure
- giving too many users membership in the `docker` group

### Disposable-VM Demo 2: Privileged Container + Host Mount = Game Over

Run only in a throwaway Linux VM:

```bash
docker run --rm -it \
  --privileged \
  --pid=host \
  -v /:/host \
  alpine:3.21 sh
```

Inside the container:

```sh
chroot /host sh
id
hostname
```

Again, this is not an advanced exploit.

It is what happens when people treat container flags as operational conveniences rather than security decisions.

## Myth 4: "Container Escapes Are Rare Edge Cases"

This is the myth that collapses as soon as you look at the runtime vulnerability timeline.

### Reality

The lesson from the advisory history is not "containers are broken forever."

The lesson is:

- the runtime is security-critical
- the bug class keeps coming back
- isolation cannot be treated as permanently solved

### Runtime Escape Timeline

#### February 11, 2019: CVE-2019-5736

`runc` allowed an attacker to overwrite the host `runc` binary and gain host root access under the right conditions. This became one of the most famous container escape examples because it destroyed the lazy belief that "container breakout is basically theoretical."

#### January 31, 2024: CVE-2024-21626

The `runc` advisory described several breakout paths caused by leaked file descriptors. The impact included host filesystem access and possible complete container escape.

#### January 31, 2024: BuildKit CVE-2024-23651, CVE-2024-23652, CVE-2024-23653

These were especially important because they moved the fear boundary earlier in the lifecycle:

- host files accessible to the build container
- host files removed outside the container
- elevated execution through BuildKit APIs under the wrong conditions

This is a crucial teaching point:

the build system is part of the attack surface.

#### July 23, 2024: CVE-2024-41110

Docker Engine had a critical authorization-plugin bypass regression. Under specific conditions, a specially crafted API request could be forwarded without the body, potentially causing the plugin to approve something it should have denied.

The lesson here is nasty and important:

even security controls around the daemon can fail.

#### November 5, 2025: Multiple New `runc` Advisories

The `runc` security overview listed three high-severity advisories published on **November 5, 2025**:

- **CVE-2025-31133**: masked-path abuse via mount race conditions
- **CVE-2025-52881**: arbitrary write gadgets and procfs write redirects leading to denial of service and escape conditions
- **CVE-2025-52565**: `/dev/console` mount-related races that could expose writable paths leading to denial of service or breakout conditions

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

## What Should Scare The Audience Most

If you want the short version of this lecture, it is this:

### 1. Misconfiguration Beats Exploitation

Most teams are more likely to be compromised by:

- exposed Docker API
- mounted Docker socket
- `--privileged`
- bind-mounting the host
- weak registry trust

than by a Hollywood-style container zero-day.

### 2. But The Zero-Days Still Exist

And when they appear, they target one of the exact things container security depends on:

- `runc`
- mount handling
- file descriptors
- BuildKit
- daemon authorization logic

### 3. The Blast Radius Is Bigger Than People Think

Bad container decisions can expose:

- the host
- the build worker
- the registry
- secrets used during build
- other workloads on the same node

## What To Say Out Loud In Class

If you want a blunt summary line for the room:

> Docker is not a sandbox. It is a very useful way to package and run processes, and if you treat it like a sandbox, it will eventually embarrass you.

And the follow-up:

> The dangerous thing about containers is not that they are always insecure. The dangerous thing is how quickly people start assuming they are secure enough by default.

## Bridge To The Rest Of The Course

This lecture should create the right mental posture for what comes next.

After this module:

- **The Image Problem** will make more sense because participants now understand that the artifact itself is part of the attack surface
- the later networking module will make more sense because host exposure and flat trust boundaries should already feel dangerous
- the hardening module will make more sense because participants now understand why runtime restrictions, secrets handling, and observability matter

This is the emotional job of the lecture:

not to make participants hate containers

but to make them stop underestimating them.

## References

- NIST SP 800-190, *Application Container Security Guide* (final, published September 25, 2017): <https://csrc.nist.gov/pubs/sp/800/190/final>
- Docker Engine security overview: <https://docs.docker.com/engine/security/>
- Docker Desktop container-isolation FAQ: <https://docs.docker.com/security/faqs/containers/>
- Docker default container user and runtime options: <https://docs.docker.com/engine/containers/run/>
- Docker Linux post-install steps warning that the `docker` group grants root-level privileges: <https://docs.docker.com/engine/install/linux-postinstall>
- Docker Rootless mode: <https://docs.docker.com/engine/security/rootless/>
- Docker daemon remote-access warning: <https://docs.docker.com/engine/daemon/remote-access/>
- Protect the Docker daemon socket: <https://docs.docker.com/engine/security/protect-access/>
- CVE-2019-5736 (`runc` host root overwrite): <https://nvd.nist.gov/vuln/detail/CVE-2019-5736>
- CVE-2024-21626 (`runc` breakout through leaked file descriptors): <https://nvd.nist.gov/vuln/detail/CVE-2024-21626>
- `runc` security overview, including November 5, 2025 advisories: <https://github.com/opencontainers/runc/security>
- CVE-2025-31133 (`runc` masked-path abuse): <https://github.com/advisories/GHSA-9493-h29p-rfm2>
- CVE-2025-52881 (`runc` arbitrary write gadgets and procfs redirects): <https://github.com/advisories/GHSA-cgrx-mc8f-2prm>
- CVE-2025-52565 (`runc` `/dev/console` mount race breakout): <https://github.com/advisories/GHSA-qw9x-cqr3-wc7r>
- CVE-2024-23651 (BuildKit host file access through cache-mount race): <https://nvd.nist.gov/vuln/detail/CVE-2024-23651>
- CVE-2024-23652 (BuildKit host file removal outside the container): <https://nvd.nist.gov/vuln/detail/CVE-2024-23652>
- CVE-2024-23653 (BuildKit elevated execution issue): <https://nvd.nist.gov/vuln/detail/CVE-2024-23653>
- CVE-2024-41110 (Docker Engine AuthZ bypass regression): <https://github.com/advisories/GHSA-v23v-6jw2-98fq>
- Microsoft case study on TeamTNT targeting exposed Docker API and unauthenticated Weave Scope, published September 8, 2020: <https://techcommunity.microsoft.com/t5/azure-security-center/teamtnt-activity-targets-weave-scope-deployments/ba-p/1645968>
