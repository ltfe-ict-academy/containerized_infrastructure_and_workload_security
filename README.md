# Containerized Infrastructure and Workload Security

A practical orientated course on containerized infrastructure and workload security, covering topics such as container security best practices, vulnerability management, runtime security, and monitoring.

## Course Outline
1. [**Container Foundations**](./01_Container_Foundations/README.md)
    - **Introduction to containers**
    - **Containers under the hood**
    - **Containers vs. VMs**
    - **Short vs. long-lived containers, cold starts, serverless architecture**
    - **Container images: understanding and building**
    - **Hands-on: preparation of containerized workloads**
    - **Hands-on: container composition**
 
2. [**Container Threat Landscape**](./02_Container_Threat_Landscape/README.md)
    - **Container Security: Myth vs. Reality**
    - **Attack surface in containerized environments**
        - The Core Idea
        - A practical model for Docker attack surface
        - Ways to analyze the threat landscape
        - Common frameworks
        - Practical overview of Docker attack surfaces
        - Common attack vectors
    - **What is S-SDLC and how it applies to containers**
    - **The Image Problem: Risks and Vulnerabilities of Container Images**
        - Images Best Practices
        - Container Image Scanning
        - Exploring insecure images in practice
    - **Container registries and supply chain attacks**

3. [**Container & Linux Networking**](./03_Container_and_Linux_Networking/README.md)
    - **Introduction to Linux Networking for Containers**
    - **Iptables and basics of the Linux kernel firewall**
    - **Docker networks, overlays, DNS**
    - **Common traps of container networking**
    - **Hands-on: Setting up a secure networking environment in a variety of configurations**

4. [**Hardening & Defense-in-Depth**](./04_Hardening_and_Defense_in_Depth/README.md)
    - **Exploiting web apps, the poster child for cloud services**
    - **Container hardening strategies**
        - Common Mistakes - practical demonstration
        - Host and daemon hardening
        - Image and Dockerfile hardening
        - Runtime and Docker Compose hardening
        - Hardened deployment example
    - **Managing Secrets in Containerized Environments**
        - Secrets fundamentals and threat model
        - How secrets leak in Docker projects
        - Environment variables, .env, and configuration boundaries
        - Docker Compose secrets
        - Build-time secrets with Docker BuildKit
        - Runtime secret consumption patterns
        - Secret storage options outside Kubernetes
        - CI/CD, scanning, and supply-chain controls
        - Rotation, revocation, auditing, and incident response
        - Example: Harden a real Docker Compose app
    - **Container Monitoring and Observability**
        - Observability concepts for Docker security
        - Native Docker monitoring and troubleshooting
        - Container health checks and service readiness
        - Prometheus, cAdvisor, and Docker metrics
        - Grafana dashboards for operations and security
        - Centralized container logging
        - OpenTelemetry and traces
        - Alerting and detection engineering
        - Docker events, daemon logs, and incident timelines
        - Runtime detection with Falco
        - Compliance, audit evidence, and CIS Docker Benchmark

5. [**Defend The Flag**](./05_Defend_The_Flag/README.md)
    - **Defend The Flag challenge for securing the containers. Applying the lessons learnt in practice.**
