# Managing Secrets In Containerized Environments

After an attacker compromises an application, one of the first questions is usually:

"what credentials can I steal from here?"

That is why secret management is not an administrative afterthought.

It is a core part of container security.

If web exploitation is the entry point and hardening limits behavior, secrets management decides how much authority is sitting nearby once the attacker lands.

## Where This Fits In Part 04

This lecture follows hardening for a reason.

The progression is:

1. web apps get compromised
2. runtime controls limit what the attacker can do
3. good secret handling limits what the attacker can steal
4. observability helps you notice and respond

This module covers step 3.

## Learning Objectives

By the end of this lecture, participants should be able to:

- identify the main ways secrets leak in containerized systems
- explain why environment variables, image layers, logs, and CI systems are common secret-exposure paths
- describe better patterns for build-time and runtime secret handling
- explain the roles of Docker secrets, Compose secrets, Kubernetes Secrets, and external secret managers
- apply practical best practices around scope, rotation, TTL, auditability, and revocation

## Suggested Timing

This module works well as a 55-60 minute lecture:

| Time | Topic |
| --- | --- |
| 0-10 min | Why secrets are the post-exploitation prize |
| 10-22 min | Where secrets leak in containerized systems |
| 22-38 min | Better patterns for build-time and runtime secret delivery |
| 38-48 min | Platform options: Docker, Compose, Kubernetes, external stores |
| 48-60 min | Rotation, revocation, and best-practice baseline |

## What Counts As A Secret Here

Participants should think broadly.

In containerized environments, secrets include:

- database passwords
- API tokens
- OAuth client secrets
- TLS private keys
- SSH keys
- cloud credentials
- registry credentials
- service account tokens
- signing keys
- webhook secrets

The danger is not only disclosure.

It is what those secrets allow next.

## Why Secrets Matter So Much After Compromise

A compromised web container may not have host root.

It may not need it.

If it has:

- database credentials
- object storage credentials
- internal API tokens
- CI tokens
- cloud keys

then the attacker can often leave the container boundary behind very quickly.

This is why secret exposure is usually an impact multiplier.

## The Main Secret Leak Paths In Containerized Systems

## 1. Secrets Baked Into Images

This is one of the worst and most common mistakes.

Examples:

- passwords copied into the image during build
- `.env` files added to the image
- private keys copied into layers
- secrets passed via `ARG` or `ENV` in a way that leaves build traces

Why it is bad:

- images are copied, cached, scanned, backed up, and shared
- a leaked image can leak the secret repeatedly
- old layers can preserve data even after later changes

If a secret ever becomes part of the image artifact, the damage is usually much larger than one running container.

## 2. Secrets Passed As Environment Variables

Environment variables are convenient.

They are also easy to overuse.

Risks:

- they can appear in process inspection
- they can leak into crash dumps or debugging output
- they can be echoed accidentally in logs
- they often get copied between environments carelessly

This does not mean environment variables are always forbidden.

It means they should not be treated as a magically secure secret transport.

## 3. Secrets In Source Repositories Or Compose Files

This sounds basic, but it still happens constantly.

Examples:

- `docker-compose.yml` contains plaintext passwords
- `.env` files are committed to Git
- secret manifests are shared because they are "just base64"

Kubernetes documents this very clearly:

base64 is not encryption.

This is an important point to say out loud in class.

## 4. Secrets Exposed In CI/CD

CI systems are one of the most dangerous secret concentration points.

Why:

- they often hold registry tokens
- build-time credentials may be present
- deployment credentials may be present
- third-party actions and plugins may run in the same workflow

A compromised CI helper can become a secret-exfiltration event long before production is touched directly.

## 5. Secrets Left In Logs

This happens through:

- debug output
- stack traces
- bad error handling
- accidental request logging
- copying full environment maps into diagnostics

Secret management fails if the application protects a password carefully and then prints it during an exception.

## 6. Over-Broad Mounted Secrets

Another common problem:

- every container in a pod or Compose project gets the same secret
- a support sidecar gets access it does not need
- a utility container gets broad file mounts "for convenience"

The rule here is very simple:

if the process does not need the secret, it should not see the secret.

## Build-Time Secrets Versus Runtime Secrets

This distinction matters a lot.

## Build-Time Secrets

These are secrets needed while building an image.

Examples:

- private package repository token
- Git credential for fetching private code
- SSH key for dependency download

The key rule:

**build-time secrets must not become part of the final image**

Docker Build supports secret and SSH mounts specifically for this reason.

## Runtime Secrets

These are secrets needed by the running workload.

Examples:

- database credentials
- API keys
- TLS keys
- service-to-service tokens

The key rule:

**runtime secrets should be delivered as late as possible, with the smallest scope possible, for the shortest lifetime possible**

## Better Build-Time Secret Handling

The modern Docker answer is BuildKit secret mounts.

This is the correct direction when builds need sensitive data temporarily.

Why it is better:

- the secret is made available to the build step without becoming a normal image layer
- it avoids common anti-patterns such as copying SSH keys or tokens into the image

The teaching point is not just "use this Docker feature."

It is:

"the build pipeline needs a separate secret-handling model from the runtime environment."

## Better Runtime Secret Handling

At runtime, good patterns usually include one of these:

- platform-managed secret mounts
- explicitly scoped secret files
- short-lived tokens from an external secret manager
- per-service credentials instead of shared global credentials

The worst pattern is:

one giant `.env` file full of long-lived production secrets reused everywhere.

## Docker And Compose Secrets

Docker and Compose both have secret concepts.

The important operational idea is that services should only get access to secrets they are explicitly granted.

In Compose, secrets are declared top-level and then granted per service.

This makes the access model much clearer than shoving everything into environment variables.

A simple mental model for students:

- configs are for configuration
- secrets are for sensitive configuration
- secret access should be explicit and minimal

## Kubernetes Secrets

Kubernetes Secrets are widely used, but they need careful teaching because many people misunderstand them.

Kubernetes documents several key facts:

- Secrets are meant for confidential data
- by default they are stored unencrypted in etcd unless encryption at rest is configured
- anyone who can create a pod in a namespace may be able to expose secrets from that namespace
- broad `list` or `watch` access to Secrets is especially dangerous

This is a very important reality check.

Kubernetes Secrets are useful.

They are not automatically a full secrets-management solution by themselves.

## External Secret Stores

Kubernetes explicitly points to the option of external secret stores and CSI-based integrations.

This matters because external stores can provide things such as:

- stronger centralization
- better auditability
- rotation workflows
- short-lived credentials
- separation of duties

Tools such as Vault go even further by offering dynamic secrets.

That is often a far better answer than long-lived shared passwords.

## Dynamic Secrets

Dynamic secrets are one of the best concepts to teach in this module.

Instead of storing a long-lived credential and hoping nobody leaks it, the platform issues:

- just-in-time credentials
- with limited scope
- with a TTL
- with revocation

This is powerful because stolen credentials expire and can be uniquely tied to a workload or request path.

That is a huge improvement over:

- shared database users
- static cloud keys
- forever-valid API tokens

## Practical Example 1: Private Dependency Download During Build

Bad pattern:

- copy an SSH key into the image
- run the dependency fetch
- delete the key later

Why this is still bad:

- the key may remain in image history or intermediate layers

Better pattern:

- use BuildKit secret or SSH mounts so the build can access the credential without baking it into the final artifact

## Practical Example 2: Database Password In Environment Variables

Bad pattern:

- same `DB_PASSWORD` used in every environment
- copied across local `.env` files, CI, and production

Better pattern:

- per-environment and ideally per-service credential
- injected at runtime only
- mounted or fetched through a platform mechanism
- rotated when staff or trust boundaries change

## Practical Example 3: Kubernetes Secret In Git

Bad pattern:

- store a base64-encoded Secret manifest in source control and treat it as protected because it is "not plain text"

Why it is bad:

- base64 is trivial to decode
- Git history makes removal painful
- repo access becomes secret access

Better pattern:

- keep the secret outside Git
- inject it at deploy time or sync it from an external store
- limit which workloads can reference it

## Practical Example 4: Shared Production API Key

Bad pattern:

- five services all use the same API key

Impact:

- one compromise affects all services
- audit attribution is poor
- rotation becomes painful

Better pattern:

- one identity per service
- ideally one credential per environment and service
- short TTL where supported

## Rotation, Revocation, And Expiry

This is where many teams fail.

They focus on secret storage but not secret lifecycle.

A mature secrets program needs:

- rotation
- revocation
- inventory
- ownership
- expiry expectations
- incident response playbooks

Good questions to ask:

- who owns this credential?
- where is it used?
- how fast can we rotate it?
- what breaks when we revoke it?

If nobody knows, the environment is fragile.

## A Practical Best-Practice Baseline

1. Never bake secrets into images or commit them to source control.
2. Use BuildKit secret or SSH mounts for build-time sensitive data.
3. Prefer explicit secret delivery over giant environment files.
4. Scope secret access per service, not per application stack.
5. Use runtime secret delivery, not build-time embedding.
6. Rotate credentials and design for revocation before the incident.
7. Prefer short-lived and dynamic credentials where possible.
8. Audit access to secrets and alert on unusual retrieval patterns.
9. Do not log secret values or full environment maps.
10. In Kubernetes, enable encryption at rest and least-privilege RBAC for Secrets.

## Good Discussion Prompts

- Which of our current secrets would be easiest to steal from a compromised container?
- Are we using environment variables because they are secure, or because they are easy?
- Which secrets are shared across too many services or environments?
- How fast could we rotate our database or API credentials after an incident?
- Which secrets today are still living in Git, CI variables, or plaintext config files?

## Bridge To The Next Module

Hardening and secrets management help reduce impact.

But we still need to answer:

- how do we notice attacks quickly?
- how do we tell normal traffic from abuse?
- how do we investigate what happened inside a container stack?

That is the job of monitoring and observability.

## Key Takeaways

- Secrets are one of the highest-value post-exploitation targets in any containerized environment.
- The most common leaks happen through images, environment handling, CI systems, logs, and over-broad access.
- Build-time and runtime secret handling are different problems and need different controls.
- Kubernetes Secrets are useful, but not magically secure by default.
- Short-lived, scoped, and revocable credentials are far safer than long-lived shared secrets.

## References

- Docker Build secrets: <https://docs.docker.com/build/building/secrets/>
- Docker Compose secrets how-to: <https://docs.docker.com/compose/how-tos/use-secrets/>
- Docker Compose secrets reference: <https://docs.docker.com/reference/compose-file/secrets/>
- Docker Swarm secrets: <https://docs.docker.com/engine/swarm/secrets/>
- Kubernetes Secrets: <https://kubernetes.io/docs/concepts/configuration/secret/>
- Good practices for Kubernetes Secrets: <https://kubernetes.io/docs/concepts/security/secrets-good-practices/>
- Kubernetes RBAC good practices: <https://kubernetes.io/docs/concepts/security/rbac-good-practices/>
- Vault, understand static and dynamic secrets: <https://developer.hashicorp.com/vault/tutorials/get-started/understand-static-dynamic-secrets>
- Vault database dynamic secrets: <https://developer.hashicorp.com/vault/tutorials/db-credentials/database-secrets>
