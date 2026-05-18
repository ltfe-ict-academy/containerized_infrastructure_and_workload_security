# Container Threat Landscape

1. [Introduction to Container Security: Myth vs. Reality](./01_Introduction_to_Container_Security_Myth_vs_Reality/README.md)
    - Myth 1: Containers are lightweight virtual machines
    - Myth 2: Containers are secure by default
    - Myth 3: Root inside a container is harmless
    - Myth 4: The Docker socket is just another file
    - Myth 5: `--privileged` just fixes annoying errors
    - Myth 6: If the image runs, the image is fine
    - Myth 7: Popular images are automatically trustworthy
    - Myth 8: Container escapes are only theoretical
    - Myth 9: Containers Reduce Complexity
2. [Attack Surface In Containerized Environments](./02_Attack_surface_in_containerized_environments/README.md)
    - Real-World Examples of Compromised Container Environments
        - Tesla Kubernetes console cryptojacking incident
        - Malicious Docker Hub images by the docker123321 account
        - Graboid Docker cryptojacking worm
        - Kinsing attacks against exposed Docker APIs
        - Hildegard TeamTNT Kubernetes campaign
        - Siloscape Windows container escape malware
        - SCARLETEEL Kubernetes-to-AWS cloud data theft
        - LemonDuck botnet targeting Docker
        - Kiss-a-Dog Docker and Kubernetes cryptojacking campaign
    - Why Containers Change the Attack Surface
    - Container Threat Model
        - Threat Actors
        - What Permissions Does Each Actor Have?
        - Ways to Analyze the Threat Landscape
        - Common Frameworks for Thinking About Container Threats
    - Practical Overview of the Docker Attack Surface
        - Source Code and Dependency Attack Surface
        - Dockerfile and Image Attack Surface
        - CI/CD and Builder Attack Surface
        - Registry and Image Distribution Attack Surface
        - Docker Host and Docker Daemon Attack Surface
        - Runtime Configuration Attack Surface
        - Network and Service Reachability Attack Surface
        - Storage, Volumes, and Host Filesystem Attack Surface
        - Secrets and Configuration Attack Surface
        - Runtime Exploits and Container Escape Attack Surface
        - Observability and Operations Attack Surface

3. [The Image Problem: Risks and Vulnerabilities of Container Images](./03_The_Image_Problem/README.md)
    - What Is A Container Image?
    - Why The Image Is The Problem
    - OCI Container Standards
        - Docker image versus OCI image
    - Inspecting OCI Images
    - Image Layers
        - Inspecting Image Layers
        - Images vs. Containers: The Writable Layer
        - Why "Deleted" Files Still Matter
    - Image naming and tagging
        - Practical Commands
    - Container Builders
        - Modern Architecture: Buildx and BuildKit
        - Attacks on the Build Machine
        - Alternative Builders and Non-Privileged Builds
    - Dockerfile: Build Instructions
        - Instructions That Create Filesystem Layers
        - Instructions That Change Image Configuration
        - Parser Directives
    - The Build Context: A Hidden Security Boundary
    - Defending the Context with `.dockerignore`
    - Multi-stage Builds
        - Example: Go Application
        - Example: Python Application
        - Multi-stage Builds and Security
    - Selecting Base Images
        - Using Docker Hardened Images
        - Using the `scratch` and the "distroless" base images
    - Rebuild your images often
    - Building Multiplatform Images
        - The Security Blind Spot in Multi-Platform Container Images
        - Hands-On Example: Multi-Architecture Build for a Go Application
    - General best practices for images
        - Treat Dockerfile changes as security-sensitive changes
        - Decouple applications
        - Create short-lived, ephemeral containers
        - Do not install unnecessary packages
        - Use a non-root `USER`
        - Be suspicious of `RUN`
        - Avoid setuid binaries
        - Avoid dependency confusion
        - Add dependency cooldowns for package freshness risk
        - Scan Dockerfiles before building
    - Generating SBOMs
        - Generating An SBOM During Docker Build
        - Generating An SBOM With Trivy
        - Generating An SBOM With Syft
    - Image Security Scanning

4. [Hands-On: Image Hardening](./04_Hands_on_image_hardening/README.md)
5. [Container Registries And Supply Chain Attacks](./05_Container_registries_and_supply_chain_attacks/README.md)
6. [Exploiting Web Apps, The Poster Child For Cloud Services](./06_Exploiting_web_apps_the_poster_child_for_cloud_services/README.md)
