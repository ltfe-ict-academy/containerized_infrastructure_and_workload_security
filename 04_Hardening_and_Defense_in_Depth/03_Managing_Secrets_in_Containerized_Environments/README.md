# Managing Secrets In Containerized Environments

In a compromised application, the first question an attacker asks is "What credentials can I steal from here?" This reality elevates secrets management from an administrative afterthought to a fundamental pillar of container security. While web exploitation serves as the entry point and system hardening restricts an attacker's movement, secrets management ultimately dictates the level of authority accessible once a perimeter is breached. By centralizing and securing sensitive data, you ensure that even if an attacker lands within your environment, the secrets remain out of reach.

## Secrets fundamentals and threat model

### What is a secret?

A secret is any value that grants access, proves identity, decrypts data, signs data, or allows one system to impersonate another. In Docker security, the most important teaching point is that secrets are not only “passwords.” A secret can be a tiny string copied into a `.env` file, a private key baked into an image layer, a CI token printed in build logs, or a certificate mounted into a container. Docker’s own documentation treats API tokens, passwords, and SSH keys as examples of sensitive values that should not be passed using Dockerfile `ARG` or `ENV`, because those mechanisms can persist in images or metadata. Some common types of secrets include:
- **API keys**: API keys are one of the easiest secrets to underestimate because they often look like harmless application configuration. In practice, an API key is usually a bearer credential: whoever has it can call the service as your application, often without proving anything else. In a Docker project, API keys commonly leak through .env files, docker-compose.yml, Docker build arguments, container logs, or example configuration copied into Git. A practical exploit is simple: an attacker finds a leaked payment, AI, email, SMS, or cloud API key in a public repository or image layer and starts making requests that generate cost, steal data, or damage reputation.
- **Database passwords**: A database password is dangerous because it often protects the most valuable part of the system: user data, business data, audit logs, sessions, and sometimes password hashes. In Dockerized applications, the classic mistake is placing POSTGRES_PASSWORD=supersecret directly in `docker-compose.yml` or an environment file that gets committed. A practical exploit does not require “hacking Docker”; the attacker simply obtains the Compose file, CI logs, backup archive, or image configuration, then connects to the database if it is reachable. Even if the database is not exposed to the internet, the password can still be useful after a second step, such as getting shell access to one container on the same Docker network. This is why database credentials should be scoped, rotated, and ideally injected at runtime.
- **OAuth client secrets**: OAuth client secrets are often misunderstood because people confuse them with OAuth client IDs. The client ID usually identifies the application and is often public; the client secret authenticates the application and must be protected. If an OAuth client secret leaks from a container image or repository, an attacker may be able to impersonate the application in token exchange flows, depending on the OAuth grant type and provider configuration. A practical example is a backend service that stores `OAUTH_CLIENT_SECRET` in a Dockerfile `ENV`. Anyone with access to the image can inspect image metadata and recover it.
- **TLS private keys**: TLS private keys are secrets because they prove the identity of a service and can sometimes decrypt captured traffic, depending on protocol versions and key exchange settings. In Docker environments, private keys often appear in bind-mounted certificate directories, reverse proxy containers, backup archives, or copied into images for convenience. A practical exploit is not always “decrypt all traffic”; often the bigger risk is impersonation. If an attacker steals the private key for `api.example.com`, they may be able to stand up a convincing fake service, intercept internal clients that trust the certificate, or abuse mutual TLS trust relationships.
- **SSH keys**: SSH keys are secrets because they often grant interactive or automated access to servers, Git repositories, deployment targets, and CI/CD systems. In Docker projects, SSH keys leak when developers copy them into images to clone private repositories during build, mount their entire `~/.ssh` directory into a container, or pass keys through build arguments. The practical exploit is straightforward: recover the private key from the image or container filesystem, then attempt access to Git, servers, or deployment infrastructure.
- **Cloud provider credentials**: Cloud credentials are especially dangerous because they often provide broad access: object storage, databases, container registries, queues, secrets managers, compute resources, and logs. In Docker, cloud credentials leak through local development mounts like `~/.aws`, CI variables, image layers, and debug logs. A practical exploit is a leaked AWS, Azure, or Google Cloud credential that lets an attacker list storage buckets, pull private container images, create compute resources for cryptomining, or read production secrets from a cloud secret manager.
- **Signing keys**: Signing keys are secrets used to prove that an artifact, token, package, image, release, or message came from a trusted source. They are high-impact because compromise can turn trust itself into an attack vector. In containerized environments, signing keys might be used for JWT signing, package signing, image signing, update signing, or webhook verification. A practical exploit is severe: if a JWT signing key leaks, an attacker may forge authentication tokens; if a release signing key leaks, an attacker may distribute malicious artifacts that appear legitimate.
- **Webhook tokens**: Webhook tokens are secrets that verify that an incoming request really came from a trusted system such as GitHub, Stripe, Slack, GitLab, or a CI/CD platform. In Docker apps, they often appear as `WEBHOOK_SECRET` in environment variables or Compose files. A practical exploit is request forgery: if the attacker knows the webhook token, they can send fake deployment events, fake payment events, fake user lifecycle events, or fake CI notifications.
- **Internal service credentials**: Internal service credentials are usernames, passwords, shared tokens, mTLS keys, or API keys used between services. Teams often treat them as lower-risk because they are “internal only,” but Docker networks make lateral movement practical. If an attacker compromises one low-privilege container and discovers internal credentials, they may authenticate to a database, cache, message queue, admin API, or another service on the same Docker network.

Not every configuration value is a secret. This distinction matters because if teams classify everything as secret, developers stop taking the label seriously. What is not usually a secret?
- Hostnames
- Port numbers
- Feature flags
- Public client IDs
- Non-sensitive environment names

### Secret lifecycle

Secrets management is not only about where a value is stored. It is a lifecycle problem: a secret is created, distributed, used, stored, rotated, revoked, expired, and eventually destroyed. [OWASP’s Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html) emphasizes lifecycle concerns such as access control, rotation, expiration, auditing, and management across systems.
- **Creation**: Secret creation is the moment where quality and ownership are established. A weak database password, overprivileged cloud key, or long-lived token starts the lifecycle already unsafe.
- **Distribution**: Distribution is how the secret gets from storage to the place where it is needed. This is where many Docker failures happen. Developers send secrets in chat, paste them into `.env` files, attach them to tickets, copy them into Compose files, or print them in CI logs.
- **Use**: Secret use is the moment the application actually reads the value. The safest pattern is usually: read the secret from a file or secret manager, use it only where needed, do not print it, do not expose it in error messages, and avoid passing it through command-line arguments.
- **Storage**: Storage is where the secret rests when it is not actively being used. Bad storage includes Git history, Docker image layers, old `.tar` exports, CI artifacts, shell history, unencrypted backups, and copied .env files on laptops.
- **Rotation**: Rotation means replacing an existing secret with a new one. Rotation matters because you rarely know exactly when a secret was copied, logged, cached, or leaked.
- **Revocation**: Revocation is different from rotation. Rotation replaces; revocation invalidates. If a secret is suspected to be leaked, the safest assumption is that someone else may already have it. A practical incident workflow is: revoke the token, identify where it was used, rotate related credentials, review logs, and remove the leak from active locations.
- **Expiration**: Expiration limits how long a secret can be useful. Short-lived credentials reduce blast radius because a stolen value becomes worthless sooner.
- **Destruction**: Destruction means removing a secret from all places it should no longer exist. This is harder than it sounds. A secret may remain in Git history, Docker image layers, build cache, registry storage, backups, logs, crash dumps, and developer laptops.

### Threat model for Dockerized apps

A Docker threat model asks: who can get access to the secret, from where, and what can they do next? [NIST SP 800-190](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf) frames containers as portable and automatable application packages, but also warns that containerized environments introduce security concerns across images, registries, orchestrators, hosts, and runtime configuration.

- **Malicious dependency**: A malicious dependency is dangerous because it runs inside your build or application with whatever access you gave the process. If your Docker build installs packages while a secret is available, a malicious install script may read that secret and exfiltrate it. If your application loads a compromised runtime dependency, it may read environment variables, mounted secret files, config directories, or cloud credentials.
- **Compromised developer machine**: A compromised developer machine is one of the most realistic secret-theft scenarios. Developers often have source code, `.env` files, SSH keys, cloud CLI sessions, package registry tokens, browser sessions, and Docker credentials on the same laptop.
- **Leaked image**: A leaked image can be as dangerous as a leaked repository, sometimes more dangerous. Images may contain compiled code, configuration, package manager caches, private dependency URLs, build metadata, and accidentally copied secrets.
- **Exposed Docker socket**: The Docker socket is one of the most important Docker security lessons. Mounting `/var/run/docker.sock` into a container often gives that container control over the Docker daemon. OWASP states that giving access to the Docker socket is equivalent to giving unrestricted root access to the host.
- **CI/CD compromise**: CI/CD systems are high-value targets because they often hold deployment credentials, registry tokens, package publishing keys, cloud credentials, signing keys, and environment secrets. A compromised pipeline can steal secrets even if the application code is clean.
- **Logs and observability leaks**: Logs are a common secret graveyard. Applications log full URLs with credentials, database connection strings, authorization headers, webhook payloads, stack traces, environment dumps, and debug configuration.
- **Runtime shell access**: Runtime shell access means an attacker, operator, or overly curious user can execute commands inside a running container. Once inside, they may inspect environment variables, mounted secret files, application configuration, process arguments, writable volumes, logs, and network access.
- **Backups and volume leakage**: Backups and volumes are often forgotten in secret threat models. Docker volumes may contain database files, uploaded files, TLS material, application config, cached tokens, or generated credentials. Backups may preserve old secrets long after rotation.

## How secrets leak in Docker projects

### Secrets in source code
Secrets in source code are the classic leak, but the Docker-specific angle is that source code often becomes part of the build context. If a developer writes an API key directly into app.py, settings.js, or config.go, that value may be copied into the image, stored in Git history, cached by CI, indexed by code search, and eventually distributed through a container registry. The exploit path is practical: an attacker does not need shell access to production; they only need access to the repository, a leaked image, or old build artifacts. Even after removing the secret from the current file, it may still exist in Git history and old images.

Example:
```bash
cd ./examples/01_secrets_in_source_code

# Initialize a new Git repository and make a commit with a secret in the source code
git init
git add app.py
git config --global user.email "you@example.com"
git config --global user.name "Your Name"
git commit -m "Add app with config"

grep -R "sk_live" .
git log -p -- app.py

# Then “fix” the file:
cat > app.py <<'PY'
import os
PAYMENT_API_KEY = os.environ.get("PAYMENT_API_KEY")
print("App started")
PY

cat app.py

# App file looks good, but the secret is still in Git history:
git add app.py
git commit -m "Move key to env"
git log -p -- app.py

# remove the git history to fully remove the secret from the repository
rm -rf .git
```

The current file is clean, but the previous commit still contains the fake key. This shows why remediation usually means rotate or revoke the secret, not just delete it from code.

### Secrets in `.env` files committed to Git

`.env` files are dangerous because they feel informal. Developers use them for local convenience, but Docker Compose automatically integrates heavily with environment-based configuration, so `.env` often becomes the place where real credentials accumulate. [Docker’s Compose documentation](https://docs.docker.com/compose/how-tos/environment-variables/best-practices/) explicitly recommends being careful with sensitive data in environment variables and considering Docker secrets for sensitive values.

Example:
```bash
cd ./examples/02_secrets_in_env_files

cat .env

cat > .gitignore <<'EOF'
.env
*.secret
secrets/
EOF

cat > .env.example <<'EOF'
POSTGRES_PASSWORD=
STRIPE_SECRET_KEY=
JWT_SIGNING_KEY=
EOF
```
A `.env.example` tells developers what variables exist without encouraging them to share real values. In many teams, `.env.example` becomes part of onboarding and CI validation.

### Secrets in `docker-compose.yml`

Putting secrets directly into `docker-compose.yml` is worse than putting them in a local `.env` file because Compose files are almost always committed, reviewed, copied, reused, and shared. A password in Compose also becomes part of the deployment definition, which means it may be visible to anyone who can read infrastructure configuration. [Docker Compose supports](https://docs.docker.com/compose/how-tos/use-secrets/) secrets and mounts them into containers as files, typically under `/run/secrets/<secret_name>`, only for services that explicitly request them.

Example:
```bash
cd ./examples/03_secrets_in_compose

cat docker-compose.yml
grep -n "PASSWORD" docker-compose.yml

# Create a secrets directory
mkdir -p secrets
printf "FAKE_compose_password_123\n" > secrets/postgres_password.txt

cat > docker-compose.yml <<'YAML'
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
    secrets:
      - postgres_password

secrets:
  postgres_password:
    file: ./secrets/postgres_password.txt
YAML

cat docker-compose.yml
```

The secret file still exists on the host. The host, developer machine, backup system, and filesystem permissions still matter.

### Secrets in Dockerfile `ENV`

Dockerfile `ENV` is a common beginner mistake because it “works.” The container starts, the application sees the variable, and everything looks fine. The problem is that `ENV` becomes part of the image metadata and is inherited by containers created from the image. [Docker’s build check documentation](https://docs.docker.com/reference/build-checks/secrets-used-in-arg-or-env/) says sensitive data should not be used in `ENV` because it persists in the final image.

![Dockerfile ENV leak](./images/secrets_in_compose.png)

Example:
```bash
cd ./examples/04_secrets_in_dockerfile

cat Dockerfile

sudo docker build -t env-leak-demo .
sudo docker inspect env-leak-demo | grep -A3 API_TOKEN

# You can also start a container and inspect the environment:
sudo docker run --name env-leak-container -d env-leak-demo
sudo docker inspect env-leak-container | grep -A3 API_TOKEN
sudo docker rm -f env-leak-container
```

Even if the application never prints the token, Docker metadata may still reveal it. This is why “we do not log the secret” is not enough if the Dockerfile itself stores the secret.

### Secrets in Dockerfile `ARG`


https://chatgpt.com/c/6a018720-14d8-8332-940c-19e939032fdf

### Secrets in image layers

### Secrets in `docker history`

### Secrets in build cache

### Secrets in logs

### Secrets in crash dumps

### Secrets in shell history

### Secrets in CI/CD job output

### Secrets in Docker inspection output

### Secrets in mounted volumes

### Secrets in container process environments

### Secrets via `/var/run/docker.sock`

## Environment variables, .env, and configuration boundaries
Participants understand when environment variables are acceptable and when they are not.

Topics

Twelve-factor configuration versus secret handling
.env files in Docker Compose
env_file
environment
shell variables
Dockerfile ENV
Dockerfile ARG
precedence and override behavior
separating config from secrets
local developer convenience versus production safety
.env.example patterns
Git hygiene:
.gitignore
.dockerignore
pre-commit hooks
example files without values
Safe naming conventions:
DB_HOST versus DB_PASSWORD
POSTGRES_PASSWORD_FILE style conventions
Why “base64 encoded” is not encrypted

Docker’s Compose documentation says to be cautious with sensitive data in environment variables and to consider Docker secrets for sensitive information; it also calls out environment-variable precedence as something teams need to understand.

## Docker Compose secrets

Participants learn practical Docker Compose secret injection without Kubernetes.

Topics

Compose secrets: top-level element
Service-level secrets: access
File-backed secrets
Environment-backed secrets
/run/secrets/<secret_name>
Per-service access control
File permissions
Secret naming conventions
Avoiding broad sharing across services
_FILE environment variable convention used by many official images
Development versus production Compose files
compose.override.yml
Multiple secret files for different environments
What Compose secrets do and do not protect against
Difference between Docker Compose secrets and a full external secrets manager

Docker Compose mounts secrets as files under /run/secrets/<secret_name> and grants access only to services that explicitly reference those secrets.

## Build-time secrets with Docker BuildKit

Participants learn how to safely use credentials during image builds without baking them into images.

Topics

Difference between build-time and runtime secrets
Why ARG and ENV are unsafe for build secrets
BuildKit overview
docker build --secret
Dockerfile RUN --mount=type=secret
Secret source from file
Secret source from environment variable
Custom target paths
SSH mounts for private Git repositories
Private package registries:
npm
pip
Maven
NuGet
private apt repositories
Build cache considerations
Multi-stage builds and secret boundaries
Verifying that secrets are not present in final image layers

Docker’s Build secrets documentation states that build arguments and environment variables are inappropriate for build secrets because they persist in the final image, and recommends secret mounts or SSH mounts instead.

## Runtime secret consumption patterns

Learning objectives

Participants learn how applications should read and use secrets once injected.

Topics

Read-on-startup model
Read-on-demand model
File watcher model
Reload without restart
Secret caching
In-memory handling
Avoiding secret logging
Avoiding secret exposure in exception messages
Masking secrets in structured logs
Redacting secrets from health checks
Avoiding secrets in command-line arguments
Avoiding secrets in URLs
File permissions and user IDs
Running as non-root
Read-only filesystem patterns
Limiting container capabilities
no-new-privileges
avoiding Docker socket mounts

OWASP recommends minimizing the time window where secrets exist in plaintext memory, while also noting that the right level of memory protection depends on the threat model and practicality.

## Secret storage options outside Kubernetes

Participants learn the main non-Kubernetes options for storing and distributing secrets.

Topics

Local file-backed secrets
Docker Compose secrets
Docker Swarm secrets, conceptually
SOPS-encrypted files
Mozilla SOPS with age or GPG
HashiCorp Vault
AWS Secrets Manager
Azure Key Vault
Google Secret Manager
1Password CLI / Doppler / Infisical style developer workflows
CI/CD secret stores
Host-level secret injection
Pull-at-startup pattern
Sidecar-like pattern without Kubernetes
Short-lived credentials
Dynamic database credentials
Trade-offs:
simplicity
auditability
rotation
offline development
blast radius
vendor lock-in
developer experience

OWASP recommends centralized secrets management, fine-grained access control, key rotation, and comprehensive auditing/monitoring across environments.

## CI/CD, scanning, and supply-chain controls
Participants learn how secrets interact with image builds, registries, pipelines, and scanners.

Topics

CI/CD secret injection
Masked variables
Protected variables
Branch and environment scoping
Pull request risks
Forked pipeline risks
Secrets in build logs
Secrets in test output
Secrets in artifacts
Secrets in Docker layer cache
Image registry access
SBOM and provenance basics
Secret scanning:
pre-commit scanning
repository scanning
CI scanning
container image scanning
Policy gates:
fail builds on detected secrets
fail builds on root containers
fail builds on unsafe Dockerfile patterns
Separation of duties:
developers can deploy without reading raw production secrets
CI can access deployment secrets only in protected contexts

NIST SP 800-190 describes application containers as portable, reusable, automatable packages and provides security recommendations for container technologies, making it a useful baseline reference for container security training.

## Rotation, revocation, auditing, and incident response

Participants move beyond “where do I put secrets?” into operational readiness.

Topics

Static versus dynamic secrets
Rotation triggers:
scheduled rotation
staff departure
suspected leak
confirmed leak
dependency compromise
environment compromise
Rotation strategies:
immediate rotation
dual-read / single-write
versioned credentials
blue-green secret rollout
application restart strategy
Revocation
Expiration
Audit logs
Access reviews
Least privilege
Break-glass access
Incident response checklist
Secret leak severity classification
Post-incident remediation

OWASP recommends regular rotation so stolen credentials are useful for a shorter time, while also noting that lifetimes vary depending on the type and purpose of the secret.

## Example: Harden a real Docker Compose app
Exercise

Participants review a sample application and classify each value as:

Secret
Sensitive but not a secret
Configuration
Public metadata
Unknown / requires policy decision


Hands-on lab

“Find the leaks” lab:

Inspect a vulnerable Docker project.
Search Git history for secrets.
Inspect image history.
Inspect runtime environment.
Review Compose files.
Review container logs.
Produce a short risk report.

Hands-on lab

Refactor a Compose app that currently uses:

environment:
  DB_PASSWORD: supersecret

into a safer design using:

.env.example
local-only ignored .env
Compose secrets for sensitive values
clear config/secret separation

Hands-on lab

Build a three-service application:

web
worker
db

Tasks:

Create separate secrets for database password, API token, and admin bootstrap password.
Grant each service only the secrets it needs.
Modify application code to read from /run/secrets.
Use _FILE style environment variables for images that support them.
Verify secrets are not present in the Compose file or image history.

Participants build an image that needs a private package token.

Bad version:

ARG NPM_TOKEN
RUN npm config set //registry.npmjs.org/:_authToken=$NPM_TOKEN

Secure version:

RUN --mount=type=secret,id=npm_token \
    NPM_TOKEN="$(cat /run/secrets/npm_token)" && \
    npm config set //registry.npmjs.org/:_authToken="$NPM_TOKEN" && \
    npm ci

Participants then inspect:

image history
final filesystem
build logs
cache behavior


Hands-on lab

Modify a small Python/Node/Go service to:

Read secrets from files.
Avoid printing secret values in logs.
Redact secrets in error output.
Fail safely if a secret is missing.
Support a restart-based rotation workflow.

Participants compare four designs for the same Docker Compose app:

Plain .env
Compose secrets from local files
Encrypted secrets in Git using SOPS
Runtime fetch from an external secret manager

They score each design against:

developer usability
production safety
auditability
rotation support
failure modes
operational complexity

Create a CI workflow that:

Builds a Docker image with BuildKit secrets.
Runs a secret scan.
Verifies no secret is present in the final image.
Publishes only if checks pass.
Uses environment-scoped secrets.

A production database password was committed to Git and used in a Docker Compose deployment.

Participants must decide:

Is this an incident?
What systems are affected?
What needs to be rotated?
What logs must be checked?
What containers must be restarted?
What evidence should be preserved?
What long-term controls should be added?

Capstone: harden a Docker Compose application

Learning objectives

Participants apply the whole course to a realistic project.

Scenario

A small company has a Docker Compose app with:

web service
background worker
PostgreSQL
Redis
private package dependency
third-party API token
CI pipeline
staging and production environments

The current project contains secrets in:

.env
docker-compose.yml
Dockerfile ARG
CI logs
image history
app logs

Capstone tasks

Participants must:

Create a secret inventory.
Remove hardcoded secrets.
Refactor runtime secrets into Docker Compose secrets.
Refactor build credentials into BuildKit secrets.
Add .env.example.
Add .gitignore and .dockerignore controls.
Add secret scanning.
Add CI/CD masking and protected variables.
Write a rotation runbook.
Write a short team policy.

Final deliverables

Hardened docker-compose.yml
Hardened Dockerfile
Secret inventory
Rotation runbook
CI/CD pipeline snippet
Risk assessment
Short presentation explaining trade-offs









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

## Key Takeaways

- Secrets are one of the highest-value post-exploitation targets in any containerized environment.
- The most common leaks happen through images, environment handling, CI systems, logs, and over-broad access.
- Build-time and runtime secret handling are different problems and need different controls.
- Kubernetes Secrets are useful, but not magically secure by default.
- Short-lived, scoped, and revocable credentials are far safer than long-lived shared secrets.
