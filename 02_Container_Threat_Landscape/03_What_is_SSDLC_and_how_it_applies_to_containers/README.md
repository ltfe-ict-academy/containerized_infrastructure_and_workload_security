# What Is S-SDLC And How It Applies To Containers

S-SDLC means **Secure Software Development Life Cycle**.

At a high level, it means security is not added at the end of the project.

It is designed into:

- requirements
- architecture
- implementation
- testing
- release
- deployment
- operations
- vulnerability response

For containerized environments, this matters even more because the thing we ship is no longer just source code.

We also ship and trust:

- Dockerfiles
- base images
- package repositories
- build pipelines
- registries
- deployment manifests
- cluster policies
- runtime configuration

That changes the development lifecycle completely.

## Where This Fits In The Course

This lecture connects the earlier threat-landscape modules with the deeper practical work that follows.

It answers a very important question:

if we now understand that containers add new attack paths, how do we systematically reduce that risk during development instead of only reacting after deployment?

## Learning Objectives

By the end of this short module, participants should be able to:

- explain what S-SDLC means in plain language
- describe why containers force security controls into more stages of the lifecycle
- map secure-development practices to container-specific artifacts such as Dockerfiles, images, registries, and manifests
- identify a small set of practical controls that teams can apply immediately
- distinguish between security theater and controls that actually reduce risk

## Suggested 20-Minute Flow

| Time | Topic |
| --- | --- |
| 0-4 min | What S-SDLC is and why "scan at the end" is not enough |
| 4-8 min | Why containers change the development lifecycle |
| 8-15 min | How to apply S-SDLC phase by phase in a container workflow |
| 15-18 min | Practical team example |
| 18-20 min | Minimum viable adoption plan |

## What S-SDLC Actually Means

The easiest wrong way to explain S-SDLC is:

"security people added a few checks to CI/CD."

That is not enough.

S-SDLC is a way of building software so that:

- fewer vulnerabilities are introduced
- design mistakes are caught earlier
- build and release steps are harder to tamper with
- security evidence is produced automatically
- deployed software is easier to trust, monitor, and fix

In other words, S-SDLC is not one tool.

It is an engineering discipline.

## Why Containers Change The SDLC

With a traditional application, many teams think in terms of:

```text
source code -> build -> deploy
```

With containers, the path looks more like this:

```text
source code
-> Dockerfile
-> base image
-> dependencies
-> build runner
-> image artifact
-> SBOM / provenance / signature
-> registry
-> deployment manifest
-> orchestrator policy
-> runtime
```

Every one of those steps is a trust decision.

That means container security is not only about runtime escape.

It is also about:

- where the base image came from
- who built the image
- whether secrets were exposed during build
- whether the image was scanned before release
- whether the deployed artifact is the same one that was tested
- whether the cluster accepts only trusted images

This is why a container-aware S-SDLC is so important.

## The High-Level Models Worth Knowing

You do not need ten frameworks in your head.

For this course, four are enough:

## NIST SSDF

NIST SP 800-218 defines the **Secure Software Development Framework** as a set of high-level secure development practices that can be integrated into any SDLC.

For teaching purposes, the most useful idea is simple:

- prepare the organization
- protect the software
- produce well-secured software
- respond to vulnerabilities

That maps very well to containerized delivery.

## OWASP SAMM

OWASP SAMM is a maturity model.

It is useful when a team asks:

"how good are we really, and what should we improve next?"

Its model covers:

- governance
- design
- implementation
- verification
- operations

That is a good lens for reviewing whether container security is ad hoc or systematic.

## SLSA

SLSA is about software supply-chain integrity.

For containers, that means asking questions such as:

- was this image built in a trustworthy build system?
- can we prove where it came from?
- do we have provenance?
- can consumers verify what they are deploying?

SLSA matters because containers are portable supply-chain artifacts.

## Secure By Design

Modern guidance from CISA pushes an important idea:

the producer must carry more of the security burden.

Applied to containers, that means teams should not expect operators to fix everything later with firewall rules and heroic YAML.

The image, defaults, pipeline, and deployment model should already be moving toward safer behavior by design.

## How To Apply S-SDLC To Containers

The best way to explain it is phase by phase.

## 1. Requirements And Planning

Before writing code, define what "secure enough" means for the containerized workload.

Practical requirements can include:

- approved base image sources
- no use of `latest` in production
- image rebuild SLA for critical CVEs
- SBOM required for release builds
- image signing required before promotion
- secrets must not be passed through Dockerfile `ARG` or `ENV`
- production pods must run with restricted security settings

This sounds basic, but many teams skip it.

Then they end up debating security during incident response instead of deciding it up front.

## 2. Architecture And Design

At design time, the team should threat-model the containerized system, not just the application logic.

Container-specific design questions include:

- which services really need network exposure?
- which component is allowed to talk to the database?
- does the app need write access to the container filesystem?
- will the workload run as root?
- where will secrets come from?
- who can push to the registry?
- who is allowed to deploy to production?
- what happens if one pod is compromised?

This is the stage where we remove entire attack paths instead of trying to detect them later.

## 3. Implementation And Build

This is where many teams make their biggest container mistakes.

Container-aware implementation practices include:

- treat the Dockerfile as security-relevant code
- pin base images to trusted versions or digests
- keep images small and purpose-built
- use multi-stage builds where appropriate
- avoid putting package managers and debug tools in production images unless needed
- never bake credentials into layers
- use BuildKit secret mounts for build-time secrets
- make builds reproducible and automated

This is also the right stage to generate evidence.

Examples:

- SBOMs
- provenance attestations
- signed image metadata

If a team cannot answer "what exactly is in this image and how was it built?" then the release process is too weak.

## 4. Verification And Testing

This is where security checks stop being optional manual reviews.

For containers, verification should include more than code scanning.

Practical verification points:

- SAST for application code
- dependency scanning for language packages
- image scanning for OS and package vulnerabilities
- secret scanning in source and image history
- misconfiguration scanning for Dockerfiles and manifests
- policy checks for Kubernetes or Compose definitions
- tests against the built container image, not only the source tree

One of the most common failures in real teams is this:

they test source code, but deploy a different artifact path than the one they verified.

That is exactly the kind of gap S-SDLC is supposed to close.

## 5. Release And Deployment

This is the moment where a container becomes a supply-chain object.

Good practices here include:

- push only to approved registries
- use immutable versioning and digests
- sign release images
- attach SBOM and provenance data
- promote the exact tested artifact between environments
- enforce deployment policy so unsigned or non-compliant images are rejected

In Kubernetes terms, this is where admission control and Pod Security Standards become highly relevant.

If the cluster accepts anything, the release process is too trusting.

## 6. Operations And Vulnerability Response

S-SDLC does not end after deployment.

For containers, operational security must include:

- monitoring for newly disclosed CVEs affecting shipped images
- rebuilding when the base image changes
- rotating credentials after exposure
- tracking which workloads are running which digests
- revoking trust in compromised images
- collecting logs and telemetry that support investigation

A container image is frozen at build time.

That is useful for consistency, but dangerous if teams confuse "immutable" with "safe forever."

## One Practical Container S-SDLC Workflow

A useful live example is a small team shipping a `web-api` container.

### Weak Process

- developer writes code
- developer writes a quick Dockerfile
- image is built locally
- image is tagged `latest`
- image is pushed to a shared registry
- production pulls and runs it

This is fast, but almost every trust decision is informal.

### Better Process

- the team uses an approved base image
- dependencies are pinned and reviewed
- the Dockerfile uses multi-stage build patterns where useful
- build-time secrets are passed with secret mounts instead of `ARG`
- CI builds the image in a controlled pipeline
- the build generates an SBOM and provenance
- vulnerability and misconfiguration checks run automatically
- the release image is signed
- deployment uses the signed digest, not a floating tag
- the platform enforces restricted runtime defaults
- operations track CVEs and trigger rebuilds when needed

That is S-SDLC applied to containers in practice.

Not perfect.

But systematic.

## Practical Controls Teams Can Start With Immediately

If a team is immature, do not give them fifty controls.

Give them a minimum viable secure container lifecycle:

1. Use approved base images and stop using random public images without review.
2. Treat Dockerfiles and deployment manifests as security-sensitive code.
3. Block secrets in Dockerfile `ARG`, `ENV`, and image layers.
4. Scan code, dependencies, images, and manifests in CI.
5. Generate SBOMs and provenance for release builds.
6. Sign production images and deploy by digest.
7. Enforce runtime restrictions and admission policy in the platform.
8. Rebuild and redeploy when upstream vulnerabilities affect your images.

That already moves a team far beyond "we ran a scanner once."

## What Teams Usually Get Wrong

These mistakes are extremely common:

- believing image scanning alone equals S-SDLC
- treating container hardening as an ops-only problem
- trusting mutable tags
- allowing developers or CI jobs to push directly to production registries without guardrails
- putting secrets in build args, environment variables, or image layers
- failing to tie the deployed image back to a tested and approved build
- forgetting that Kubernetes manifests and Compose files are part of the attack surface
- patching running containers manually instead of rebuilding from source

If you want one sentence to remember, use this one:

**S-SDLC for containers means securing the path to the image, the image itself, and the path from the image into production.**

## A Good High-Level Mental Model

Use this simple checklist:

```text
Can we trust:
- the source?
- the dependencies?
- the Dockerfile?
- the build system?
- the image artifact?
- the registry?
- the deployment manifest?
- the runtime policy?
- the response process after a CVE drops?
```

If the answer is "not really" for several of those, the team does not yet have a secure container SDLC.

## Bridge To The Rest Of The Course

This module is intentionally high level.

The rest of the course turns each part into practice:

- **The Image Problem** goes deeper into the artifact we build and trust
- the networking module reduces unnecessary exposure and lateral movement
- the hardening module tightens runtime controls, secrets handling, and observability
- the hands-on track turns the theory into an end-to-end build, break, and harden workflow

## References

- NIST SP 800-218, *Secure Software Development Framework (SSDF) Version 1.1*: <https://csrc.nist.gov/pubs/sp/800/218/final>
- NIST SP 800-190, *Application Container Security Guide*: <https://csrc.nist.gov/pubs/sp/800/190/final>
- OWASP SAMM model overview: <https://owaspsamm.org/model/>
- SLSA overview: <https://slsa.dev/>
- CISA Secure by Design guidance: <https://www.cisa.gov/resources-tools/resources/secure-by-design>
- Docker Build secrets: <https://docs.docker.com/build/building/secrets/>
- Docker build attestations, SBOM, and provenance: <https://docs.docker.com/build/metadata/attestations/>
- Docker SBOM attestations: <https://docs.docker.com/build/metadata/attestations/sbom/>
- Sigstore Cosign container signing: <https://docs.sigstore.dev/cosign/signing/signing_with_containers/>
- Kubernetes Pod Security Standards: <https://kubernetes.io/docs/concepts/security/pod-security-standards/>
