# Container Hardening Strategies

If the previous module explained how attackers get in, this module explains how to make that foothold less useful.

Container hardening is not one setting.

It is a collection of choices that reduce:

- privilege
- reachability
- writable surface
- abuse of the kernel boundary
- blast radius after compromise

Good hardening does not make exploitation impossible.

It makes post-exploitation slower, noisier, and less damaging.

## Where This Fits In Part 04

This module is the defensive backbone of the day.

The red line is:

1. web exploitation gets the attacker into the workload
2. hardening limits what the workload can do after compromise
3. secret management removes some of the most valuable post-exploitation targets
4. observability tells you when hardening was bypassed or is being tested

This module covers step 2.

## Learning Objectives

By the end of this lecture, participants should be able to:

- explain what container hardening is really trying to achieve
- identify the main hardening layers for Docker-based workloads
- apply practical runtime restrictions that materially reduce risk
- explain the value of non-root execution, capability reduction, read-only filesystems, seccomp, AppArmor, and resource limits
- distinguish meaningful hardening from security theater

## Suggested Timing

This module works well as a 60-65 minute lecture:

| Time | Topic |
| --- | --- |
| 0-10 min | What hardening is and what it is not |
| 10-22 min | Image and process hardening basics |
| 22-38 min | Runtime restrictions that matter most |
| 38-50 min | Host and daemon hardening |
| 50-65 min | Practical baseline, common mistakes, best practices |

## What Hardening Is Really About

The wrong mental model is:

"we add a few flags and become secure."

The right mental model is:

"we remove power the application does not legitimately need."

That usually means:

- less privilege
- fewer syscalls
- fewer writable paths
- fewer capabilities
- less network exposure
- less host coupling

In other words, container hardening is mostly the art of saying **no** to unnecessary power.

## The Hardening Layers

For a Docker-focused course, teach hardening in five layers:

1. image hardening
2. process and privilege hardening
3. filesystem and runtime hardening
4. daemon and host hardening
5. policy and operational hardening

That structure helps people avoid treating hardening as only an image problem or only a runtime flag problem.

## 1. Image Hardening

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

## 2. Run As A Non-Root User

This is one of the simplest and most valuable hardening steps.

If the application does not truly need root inside the container, do not give it root.

Benefits:

- fewer easy privilege abuses inside the container
- less damage from accidental file writes
- stronger alignment with least privilege

This also forces engineering discipline because applications that assume root often reveal other hidden design weaknesses.

## 3. Avoid `--privileged` And Host Namespace Sharing

This should be taught as a bright red warning.

Avoid:

- `--privileged`
- `--pid=host`
- `--network=host` unless truly necessary
- mounting the Docker socket
- broad host-path mounts

These settings often turn a container into "just a process on the host with extra packaging."

When teams use them casually, they are trading away much of the isolation containers were supposed to provide.

## 4. Drop Capabilities Aggressively

Linux capabilities split privileged operations into smaller units.

Docker already drops many capabilities by default, but secure workloads should go further when possible.

Best-practice mindset:

- drop all capabilities you do not need
- ideally `drop all` and add back only what is required

Why it matters:

- many container escapes and abuse paths rely on privilege that is broader than the app actually needs
- extra capabilities can make kernel interaction, network manipulation, or filesystem abuse easier

## 5. Prevent In-Container Privilege Escalation

Use `no-new-privileges`.

This helps stop the process from gaining new privileges through mechanisms such as `setuid` or `setgid`.

That matters because a surprisingly large number of applications carry helper binaries or package leftovers they never meant to expose in a production threat model.

## 6. Use Seccomp, AppArmor, Or SELinux

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

## 7. Make The Root Filesystem Read-Only When Possible

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

## 8. Limit Resource Abuse

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

## 9. Control The Network Surface

Networking is part of hardening, not a separate concern.

A runtime with weak privilege settings but overly broad network reach is still dangerous.

Basic network hardening patterns:

- publish only what must be exposed
- bind local-only ports to loopback
- segment services onto the minimum necessary networks
- keep data stores off edge-facing networks
- review egress as well as ingress

This is where Part 03 and Part 04 connect directly.

## 10. Protect The Docker Daemon And Socket

The Docker daemon is a high-value control plane.

If an attacker gets access to it, many other hardening controls become irrelevant.

High-priority rules:

- do not expose the Docker socket to containers
- do not expose the Docker API remotely unless there is a very good reason
- if remote access is necessary, use strong authenticated protection such as SSH or TLS
- keep daemon access tightly restricted

This is one of the most common "convenience shortcuts" that destroys the whole security model.

## 11. Rootless Mode And User Namespace Isolation

Docker supports rootless mode and user-namespace remapping.

These are related but not identical ideas.

High-level difference:

- **rootless mode** runs the daemon and containers as an unprivileged user
- **userns-remap** maps container root to an unprivileged host user range while the daemon itself still runs with elevated privileges

Both can reduce the blast radius of certain host-impacting failures.

The key teaching point is:

if you have not thought about this topic at all, your hardening posture is probably immature.

## 12. Keep Host And Engine Updated

This sounds boring.

It is not.

Containers share the host kernel.

That means old kernels and old container runtimes directly undermine your security posture.

Hardening that ignores patch level is mostly cosmetics.

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

## Common Hardening Mistakes

These show up constantly:

- running everything as root because it is easier
- using `--privileged` to make problems go away
- mounting Docker socket into app or CI containers
- leaving shells and package managers in production images without a reason
- disabling default seccomp or AppArmor profiles
- forgetting resource limits
- mounting large parts of the host filesystem
- publishing ports widely and calling the environment "hardened"

If a team does several of these, the environment is only cosmetically hardened.

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

## Kubernetes Note

This course is Docker-centered, but participants should still hear the broader point:

Kubernetes Pod Security Standards encode the same philosophy.

The **Restricted** profile is essentially the platform saying:

"containers should not get powerful defaults unless they truly need them."

That is the same mindset you want on a single-node Docker deployment.

## Good Discussion Prompts

- Which of our current containers are still running as root?
- Where are we using host mounts or Docker socket mounts for convenience?
- Which services could move to a read-only root filesystem with only small engineering work?
- Which workloads truly need extra Linux capabilities?
- If one app container were compromised today, which runtime control would slow the attacker down the most?

## Bridge To The Next Module

After hardening, the next thing attackers usually want is credentials.

That is why the next module is about:

- build-time secrets
- runtime secrets
- environment variables
- mounted secret files
- rotation
- dynamic credentials

If hardening limits what the attacker can do, secret management limits what they can steal.

## Key Takeaways

- Container hardening is about removing unnecessary power from the workload.
- The biggest wins usually come from non-root execution, capability reduction, read-only filesystems, and avoiding dangerous host coupling.
- Seccomp, AppArmor, and related kernel controls are real security boundaries and should not be disabled casually.
- Resource limits and network design are part of hardening, not optional extras.
- A hardened container is still exploitable if the app is vulnerable, but it is much harder to abuse effectively.

## References

- Docker Engine security overview: <https://docs.docker.com/engine/security/>
- Docker rootless mode: <https://docs.docker.com/engine/security/rootless/>
- Docker user namespace remapping: <https://docs.docker.com/engine/security/userns-remap/>
- Docker seccomp security profiles: <https://docs.docker.com/engine/security/seccomp/>
- Docker AppArmor profiles: <https://docs.docker.com/engine/security/apparmor/>
- Protect the Docker daemon socket: <https://docs.docker.com/engine/security/protect-access/>
- Docker resource constraints: <https://docs.docker.com/engine/containers/resource_constraints/>
- Docker Compose services reference: <https://docs.docker.com/reference/compose-file/services/>
- OWASP Docker Security Cheat Sheet: <https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html>
- NIST SP 800-190, *Application Container Security Guide*: <https://csrc.nist.gov/pubs/sp/800/190/final>
- Kubernetes Pod Security Standards: <https://kubernetes.io/docs/concepts/security/pod-security-standards/>
- Docker minimal or distroless images: <https://docs.docker.com/dhi/core-concepts/distroless/>
