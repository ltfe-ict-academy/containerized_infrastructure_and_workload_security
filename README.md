# Containerized Infrastructure and Workload Security

A practical orientated course on containerized infrastructure and workload security, covering topics such as container security best practices, vulnerability management, runtime security, and monitoring.

## Course Outline
1. [**Container Foundations**](./01_Container_Foundations/README.md)
    - Introduction to containers
    - Containers under the hood
    - Containers vs. VMs
    - Short vs. long-lived containers, cold starts, serverless architecture
    - Container images: understanding and building
    - Hands-on: preparation of containerized workloads
    - Hands-on: container composition 
 
2. [**Container Threat Landscape**](./02_Container_Threat_Landscape/README.md)
    - Container Security: Myth vs. Reality 
    - Attack surface in containerized environments 
    - What is S-SDLC and how it applies to containers
    - The Image Problem: Risks and Vulnerabilities of Container Images  
    - Container registries and supply chain attacks
    - Hands-on: exploring insecure images in practice
    - Hands-on: demonstrating container escape vulnerabilities

3. [**Container & Linux Networking**](./03_Container_and_Linux_Networking/README.md)
    - Introduction to Linux Networking for Containers 
    - Iptables and basics of the Linux kernel firewall
    - Docker networks, overlays, DNS 
    - Common traps of container networking
    - Hands-on: Setting up a secure networking environment in a variety of configurations

4. [**Hardening & Defense-in-Depth**](./04_Hardening_and_Defense_in_Depth/README.md)
    - Exploiting web apps, the poster child for cloud services 
    - Container hardening strategies 
    - Managing Secrets in Containerized Environments 
    - Container Monitoring and Observability
    - Practical examples of end-to-end exploitation, hardening and observability

5. [**Defend The Flag**](./05_Defend_The_Flag/README.md)
    - Defend The Flag challenge for securing the containers. Applying the lessons learnt in practice.
