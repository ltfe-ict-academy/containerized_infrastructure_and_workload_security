# Container Registries And Supply Chain Attacks

Container registries look simple.

Push image.

Pull image.

Done.

That simplicity is deceptive.

A registry is not just storage.

It is a **trust distribution system**.

The moment a team says:

"production will pull whatever is in that repository"

the registry becomes part of the security boundary.

And once that happens, an attacker no longer needs direct access to your cluster if they can:

- publish a malicious image
- overwrite a trusted tag
- steal the token that pushes release artifacts
- compromise the build pipeline that feeds the registry
- poison the software that goes into the image before it is ever pushed

This module is about that problem.

## Where This Fits In The Course

This lecture follows **The Image Problem**.

That is intentional.

The previous module asks:

"what is inside the image, and why can that be dangerous?"

This module asks the next question:

"how does a dangerous image become trusted, distributed, and deployed?"

That is the supply-chain question.

## Learning Objectives

By the end of this lecture, participants should be able to:

- explain why a registry is a security-sensitive component and not just a storage backend
- identify the main registry-specific risks in real environments
- describe several common supply-chain attack paths that end with malicious container deployment
- explain how recent real-world incidents worked and why they were so damaging
- apply practical controls such as tag immutability, scoped credentials, signing, provenance, policy enforcement, and controlled promotion

## Suggested 40-Minute Flow

| Time | Topic |
| --- | --- |
| 0-5 min | Why registries matter so much |
| 5-12 min | The registry threat model |
| 12-22 min | Common registry and supply-chain failure modes |
| 22-32 min | Real-world attack examples and impact |
| 32-37 min | How to protect registries and image promotion |
| 37-40 min | Key takeaways and discussion |

## The Core Idea

In a containerized environment, the registry is often the point where:

- build output becomes deployment input
- development trust becomes production trust
- mutable names are mapped to immutable content
- operators assume authenticity

That makes the registry a perfect target.

An attacker does not always need to hack the registry service itself.

They can win by compromising any point that can influence what lands in the registry or what gets pulled from it.

## What A Registry Actually Represents

From an operations perspective, a registry stores:

- repositories
- tags
- digests
- manifests
- layers
- metadata
- sometimes signatures, SBOMs, and attestations

From a security perspective, a registry represents:

- a source of deployable truth
- a set of identities allowed to publish software
- a policy boundary around public versus private artifacts
- an audit point for what was released and when
- a high-value bridge between CI/CD and runtime

If that bridge is weak, everything after it is suspect.

## Why Registries Are So Dangerous When Misunderstood

Teams often say:

- "we use a private registry, so we are safer"
- "the image came from our repository, so it is trusted"
- "we scan images, so supply-chain risk is covered"

All three can be false.

A private registry can still be poisoned.

An internal repository can still contain malicious or tampered artifacts.

And scanning alone does not prove:

- who built the image
- what source produced it
- whether the pushed image is the one that was tested
- whether the tag still points to the same content

## The Registry Threat Model

Think of the registry in four directions at once:

```text
Upstream  -> base images, package ecosystems, external artifacts
Build     -> CI/CD, builders, release automation, signing
Registry  -> repos, tags, auth, immutability, scanning, access control
Runtime   -> orchestrator pulls, admission, nodes, workloads, rollback paths
```

An attacker can interfere in any of those directions.

So registry security is never only "protect the registry login page."

It is:

- protect what gets in
- protect who can change it
- protect how consumers verify it
- protect how fast you can detect and revoke bad artifacts

## Common Registry Problems In Practice

## 1. Blind Trust In Public Registries

Public registries are useful, fast, and dangerous.

Common mistakes:

- pulling images directly from public namespaces without review
- assuming a popular image is automatically safe
- assuming an image name means the publisher is legitimate
- using images maintained by unknown individuals in production
- trusting community images that lag patches or include extra software

The real problem is not only malware.

It is also hidden build logic, stale dependencies, unclear maintenance, poor provenance, and silent drift over time.

## 2. Mutable Tags

Tags are convenient labels, not cryptographic identities.

This is one of the most important lessons in the whole course.

If you deploy `myapp:prod` or `scanner:latest`, you are trusting that the meaning of that label will not change behind your back.

But unless you enforce immutability, it can.

That enables:

- accidental overwrites
- malicious retagging
- rollback confusion
- stealthy replacement of trusted content

An attacker loves mutable tags because they let bad content masquerade as a normal update.

## 3. Overpowered Registry Credentials

Registry credentials are often handled terribly.

Common problems:

- long-lived tokens in CI variables
- shared human accounts used by automation
- push and delete rights where pull-only would be enough
- tokens copied into many pipelines
- no expiration
- no per-repository scoping
- no easy revocation path

If an attacker steals a registry push token, they may not need cluster access at all.

They can simply publish a new image and wait for the next deployment or restart.

## 4. Compromised CI/CD Feeding The Registry

In modern environments, the registry usually trusts the CI pipeline.

That means the build system becomes a publishing authority.

If CI/CD is compromised, the attacker can:

- alter the Dockerfile
- change the source at build time
- inject malicious dependencies
- replace tags
- publish malicious images through legitimate automation
- attach misleading SBOMs or metadata

This is one of the most dangerous patterns because the registry logs may still show authenticated, expected activity.

## 5. Weak Separation Between Build Stages

Many teams use one repository for:

- development builds
- test builds
- staging images
- production releases

That creates confusion and risk.

If every environment pulls from the same namespace with weak promotion rules, then:

- test artifacts can leak into production
- unreviewed images can be deployed
- rollback history becomes unreliable
- trust boundaries disappear

Production registries should not behave like a shared scratchpad.

## 6. No Cryptographic Verification

Without signatures or attestations, a consumer often knows only:

- the repository name
- the tag
- maybe the digest after pull

That is not enough to prove:

- who built the image
- whether it came from the expected workflow
- whether it was approved
- whether it was tampered with before deployment

Unsigned containers are very often "trusted" only because they live in the right place.

That is weak security.

## 7. No Provenance

Even signed images are not the full answer if no one can answer:

- what source commit produced this image?
- which workflow built it?
- which dependencies were present?
- was the build reproducible or isolated?

Provenance matters because incident response depends on traceability.

If you cannot reconstruct how an image came into existence, you will struggle to decide whether to trust it.

## 8. Registry Scanning Treated As A Silver Bullet

Registry scanning is useful.

It is not enough.

A scanner may detect:

- known CVEs
- package metadata issues
- outdated dependencies

It may not detect:

- malicious but otherwise functional code
- stolen publisher credentials
- retagging abuse
- secret exfiltration logic hidden in entrypoints
- compromised build workflows

Supply-chain attacks often succeed precisely because the artifact still "works."

## 9. Pull By Tag Instead Of Digest

This mistake is everywhere.

If runtime pulls by tag, you increase the gap between:

- what was tested
- what was approved
- what was actually deployed

Pulling by digest makes the deployment refer to exact content.

Pulling by tag delegates too much trust to mutable naming.

## 10. Registry Access Rules That Are Too Open

Common real-world issues:

- anyone in the engineering org can push release images
- the same credentials are used for both CI and local developer machines
- external systems can pull from sensitive registries with broad tokens
- no IP restrictions, no allowlists, no segmented access
- no audit review of pushes, deletes, or tag changes

When too many identities can publish, attribution collapses and detection becomes slower.

## 11. Pull-Through Mirrors And Cached Content Nobody Monitors

Organizations often use:

- mirrors
- proxies
- caches
- local copies of upstream registries

These are useful for performance and resilience, but they also become trust amplifiers.

If they cache poisoned content or bypass verification, they can spread bad artifacts internally at scale.

## 12. Registry Availability And Operational Risk

Supply-chain security is not only integrity.

It is also availability and recovery.

If a registry is unavailable, rate-limited, or loses artifacts:

- deployments fail
- scaling fails
- rollback fails
- incident response slows down

This matters because under pressure, teams often disable controls "temporarily" to get systems running again.

That is when bad artifacts slip through.

## How Supply Chain Attacks Reach Registries

The registry is often the visible end of a longer compromise.

A few common paths:

## Path 1: Credential Theft -> Malicious Push

1. The attacker steals CI or maintainer credentials.
2. They authenticate to the registry or release pipeline as a legitimate publisher.
3. They publish or retag malicious content.
4. Runtime pulls the image because the repository and tag still look trusted.

## Path 2: Build Pipeline Compromise -> Trusted Artifact Poisoning

1. The attacker compromises the build workflow, build runner, or dependency used during build.
2. The pipeline produces a malicious artifact.
3. The registry stores it as a normal release.
4. Everyone downstream consumes attacker-controlled content.

## Path 3: Upstream Dependency Compromise -> Base Image Poisoning

1. A package, library, or base image is compromised upstream.
2. Internal images rebuild with the poisoned dependency.
3. Registry scanning may miss the malicious logic if it is not a known vulnerability.
4. The organization distributes the backdoor to itself.

## Path 4: Tag Reassignment -> Silent Drift

1. The attacker does not need a new image name.
2. They move a trusted tag to a different digest.
3. Existing automation continues to deploy the trusted label.
4. The image changes while dashboards, docs, and habits still refer to the old tag name.

## Path 5: CI Helper Compromise -> Registry Token Theft

1. A GitHub Action, scanner, build plugin, or helper script is compromised.
2. Secrets from the runner are exposed.
3. Registry tokens are stolen.
4. Malicious images are pushed or promoted through legitimate channels.

This is why supply-chain attacks often feel unfair:

the organization may have hardened runtime reasonably well, but still loses because it trusted the wrong build component.

## A Practical Attack Chain

Use this scenario with participants:

```text
Compromised GitHub Action
-> CI secrets exposed
-> registry push token stolen
-> trusted image tag overwritten
-> production deployment pulls new image
-> malicious code exfiltrates cloud credentials
-> attacker pivots into the environment
```

Notice what did **not** need to happen:

- no Kubernetes API exploit
- no container escape
- no node-level kernel exploit

The attacker won much earlier.

## Real-World Example 1: Trivy Supply Chain Compromise In March 2026

This is one of the best recent examples for this module because it hit exactly the trust path many teams rely on.

According to Docker and Microsoft:

- on **March 19, 2026**, attackers compromised Aqua Security’s CI/CD pipeline
- malicious Trivy artifacts were distributed through official channels
- affected channels included **GitHub**, **npm**, and **Docker Hub**
- Docker reported that Docker Hub users who pulled `aquasec/trivy` with tags `0.69.4`, `0.69.5`, `0.69.6`, and `latest` between **March 19, 2026 at 18:24 UTC** and **March 23, 2026 at 01:36 UTC** may have been exposed
- Microsoft reported the malicious releases harvested CI/CD secrets, cloud credentials, SSH keys, Docker configuration, Kubernetes service-account material, and other sensitive data

Why this case matters:

- the image came from an official source
- the tags looked normal
- the scanner still appeared to function
- the compromise happened in the distribution path people trusted most

This is the nightmare scenario for registry trust.

The lesson is brutal:

**an official repository is not enough if the publisher pipeline is compromised.**

## Real-World Example 2: tj-actions/changed-files In March 2025

This incident was not a container registry attack by itself.

It was a supply-chain compromise in a popular GitHub Action.

That is exactly why it matters here.

CISA warned that the compromise of `tj-actions/changed-files` allowed disclosure of secrets including:

- access keys
- GitHub personal access tokens
- npm tokens
- private RSA keys

Why this matters for registries:

- CI runners often hold registry push credentials
- if a build helper leaks secrets, attackers can move from CI compromise to artifact publishing
- many organizations would detect the CI issue late, after malicious images had already been published or promoted

In other words, not every registry compromise starts at the registry.

Many start in the automation around it.

## Real-World Example 3: XZ Backdoor In 2024

The XZ backdoor is a powerful teaching example because it shows how far upstream a supply-chain attack can begin.

OpenSSF described it as malicious code inserted into upstream `xz/liblzma`.

Why it matters to container teams:

- many base images and build environments rely on upstream Linux packages
- an upstream compromise can flow into images during normal rebuilds
- the registry then becomes a distribution hub for a problem the organization did not create but still shipped

This is the hard truth:

you can publish poisoned images into your own trusted registry without any attacker ever logging into that registry.

## How These Attacks Are Often Done

Participants usually imagine supply-chain attacks as exotic.

Many are not.

The most common patterns are boring and effective:

## 1. Steal Maintainer Or CI Credentials

Examples:

- phishing
- token theft from CI variables
- exposed secrets in logs
- stolen laptop session
- compromised self-hosted runner

Impact:

- malicious releases published as legitimate
- signed-in user activity looks normal in logs

## 2. Abuse Mutable Tags

Examples:

- repoint `latest`
- overwrite `stable`
- move a version tag after a cleanup attempt

Impact:

- trusted automation pulls new content without any code change in the deployment repo

## 3. Poison Build Inputs

Examples:

- malicious package in language ecosystem
- compromised base image
- compromised action or plugin in CI
- hostile script fetched during build

Impact:

- malicious content reaches the registry through a normal build

## 4. Exploit Weak Promotion Rules

Examples:

- developers can push directly into production repositories
- staging and production share the same registry path
- no approval gate between build and release

Impact:

- unreviewed or malicious artifacts become deployable immediately

## 5. Hide In Legitimate Functionality

This is why scanners and human reviewers both miss attacks.

The malicious image still:

- starts correctly
- passes basic health checks
- performs the expected task

Meanwhile it also:

- steals secrets
- opens a reverse shell
- sends metadata off-box
- downloads a second stage

## The Impact When Registry Trust Fails

When a registry or release path is compromised, the blast radius can be enormous.

Potential impact includes:

- deployment of backdoored applications
- theft of cloud credentials
- theft of Kubernetes secrets
- lateral movement into production environments
- theft of source code or customer data
- supply-chain spread into customer environments
- loss of release integrity and rollback confidence
- incident response paralysis because teams no longer know which artifacts are safe

This is one reason supply-chain incidents feel worse than ordinary app bugs.

They attack the mechanism used to distribute trust.

## How To Protect Container Registries In Practice

Protection has to cover both the registry itself and the artifact path around it.

## 1. Enforce Strong Identity Controls

At a minimum:

- enable MFA for human registry accounts
- use organization-owned automation tokens instead of personal accounts
- scope tokens narrowly by repository and action
- expire tokens
- rotate tokens aggressively after incidents
- separate pull-only identities from push-capable identities

If a developer leaves the company and production builds still depend on that person’s personal token, the process is broken.

## 2. Make Tags Immutable Where Possible

This is a major practical control.

If tags are immutable, attackers lose an easy stealth mechanism.

Good pattern:

- use semantic version tags for humans
- enforce immutability on release tags
- deploy by digest in production

That gives readability without sacrificing integrity.

## 3. Promote Images, Do Not Rebuild Them Per Environment

The artifact tested in CI should be the artifact promoted to staging and production.

Do not rebuild "the same image" three times and assume they are identical.

Promotion should preserve:

- digest
- signature
- provenance
- approval history

## 4. Sign Images And Verify Before Deployment

Signing matters because it lets consumers ask:

- was this image published by an expected identity?
- is this the exact artifact that was approved?

Verification matters even more.

Signed artifacts that nobody checks are only decorative.

In practice, pair:

- image signing
- provenance attestations
- admission or deployment policy that rejects untrusted artifacts

## 5. Generate And Retain Provenance

A production image should be traceable back to:

- source repository
- commit
- workflow
- builder identity
- time of build

This is where SLSA-style thinking becomes useful.

Without provenance, investigations turn into guesswork.

## 6. Scan, But Do Not Stop At Scanning

Use registry or pipeline scanning for:

- known vulnerabilities
- stale base images
- policy failures

But remember:

- scanners do not prove authenticity
- scanners do not prevent tag tampering
- scanners do not stop malicious but fully functional code

Scanning is one control in a chain, not the chain.

## 7. Separate Repositories By Trust Level

Useful separation patterns:

- external mirror versus internal approved base images
- dev versus staging versus production release repositories
- quarantine area for newly built images
- curated "golden base image" repository

This reduces accidental trust expansion.

## 8. Restrict Registry Reachability And Publishing Paths

Practical controls:

- do not let every environment push
- restrict which builders can access release repositories
- review webhooks and automation hooks
- segment private registries from broad internal access where possible
- monitor unusual push, delete, or retag activity

## 9. Pin And Verify CI Components

Because many registry compromises start in CI:

- pin GitHub Actions by commit SHA when possible
- review third-party pipeline actions
- prefer reusable, centrally controlled workflows
- isolate high-trust release jobs from general CI
- use ephemeral runners for sensitive builds

## 10. Prepare For Revocation And Recovery

Ask these questions before the incident:

- how do we identify every workload using a compromised digest?
- how do we block further pulls of a bad artifact?
- how do we revoke trust in a signature or publisher?
- how fast can we rotate registry tokens?
- how do we rebuild from known-good source and inputs?

If the answer is "manually, slowly, and with spreadsheets," the response plan is weak.

## A Practical Minimum Standard

If a team wants a realistic baseline, use this:

1. Use approved registries only.
2. Enable MFA and strong org-level identity controls.
3. Use short-lived or scoped automation tokens.
4. Make release tags immutable.
5. Deploy by digest, not floating tags.
6. Sign release images and generate provenance.
7. Enforce verification at deployment or admission time.
8. Separate dev, staging, and production image paths.
9. Monitor pushes, deletes, retags, and unusual access.
10. Maintain a fast response process for bad artifacts and stolen credentials.

That will not make supply-chain attacks impossible.

But it will make them much harder to execute quietly.

## Good Discussion Prompts

- Which is more dangerous in our environment today: compromised CI, compromised registry credentials, or compromised upstream dependencies?
- If a trusted image tag were silently changed tonight, how would we notice?
- Can our runtime prove who built the image it is running?
- Are we deploying the exact tested artifact, or only something with the same name?
- Which third-party CI helpers currently have access to secrets or publishing credentials?

## Bridge To The Rest Of The Course

This module should make one thing obvious:

registry security is really release integrity security.

After this lecture:

- the hands-on work on insecure and hardened image workflows should make more sense
- the networking and hardening modules should feel like downstream defenses, not the first line of trust
- the final challenge can treat artifact trust, provenance, and promotion as part of realistic defense

If participants leave with one lasting idea, let it be this:

**the container registry is where supply-chain trust becomes operational reality**

and if that trust is weak, the rest of the stack inherits the weakness.

## References

- NIST SP 800-190, *Application Container Security Guide*: <https://csrc.nist.gov/pubs/sp/800/190/final>
- SLSA overview: <https://slsa.dev/>
- Sigstore overview: <https://docs.sigstore.dev/>
- Docker: What is a registry?: <https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-registry/>
- Docker Hub immutable tags: <https://docs.docker.com/docker-hub/repos/manage/hub-images/immutable-tags/>
- Docker Hub personal access tokens: <https://docs.docker.com/docker-hub/access-tokens/>
- Docker Hub organization access tokens: <https://docs.docker.com/enterprise/security/access-tokens/>
- Docker account two-factor authentication: <https://docs.docker.com/security/2fa/>
- Docker Hub image security insights and scanning: <https://docs.docker.com/docker-hub/repos/manage/vulnerability-scanning/>
- Kubernetes images documentation, including default registry behavior and digest usage: <https://kubernetes.io/docs/concepts/containers/images/>
- GitHub artifact attestations: <https://docs.github.com/en/actions/concepts/security/artifact-attestations>
- Docker incident write-up, *Trivy supply chain compromise: What Docker Hub users should know*, published March 23, 2026: <https://www.docker.com/blog/trivy-supply-chain-compromise-what-docker-hub-users-should-know/>
- Microsoft incident analysis, *Guidance for detecting, investigating, and defending against the Trivy supply chain compromise*, published March 24, 2026: <https://www.microsoft.com/en-us/security/blog/2026/03/24/detecting-investigating-defending-against-trivy-supply-chain-compromise/>
- CISA alert on `tj-actions/changed-files` and `reviewdog/action-setup`, last revised March 26, 2025: <https://www.cisa.gov/news-events/alerts/2025/03/18/supply-chain-compromise-third-party-tj-actionschanged-files-cve-2025-30066-and-reviewdogaction>
- OpenSSF write-up, *xz Backdoor CVE-2024-3094*, published March 30, 2024: <https://openssf.org/blog/2024/03/30/xz-backdoor-cve-2024-3094/>
