# Defend The Flag: Harden A Self-Hosted DefectDojo Deployment

## Scenario

You have received a Linux VM with a public IP address. Your task is to deploy a hardened DefectDojo environment using Docker Compose.

DefectDojo is a vulnerability-management and DevSecOps platform. In a real organization, it can contain scan results, application names, engagement history, vulnerability details, remediation notes, reports, user accounts, API tokens, and integrations with other systems. That makes it a sensitive system. If DefectDojo is exposed badly, an attacker may not only compromise one application; they may gain a map of the organization’s weaknesses.

The goal of this challenge is not simply to make DefectDojo run. The goal is to make it run with a hardened container deployment, a hardened host, a clear network design, private administrative access, strong secrets handling, and useful monitoring.

The final deployment must follow this rule:

> The DefectDojo website is public over HTTP/HTTPS. Dockhand, Grafana, and all administrative interfaces are accessible only through VPN. Databases, brokers, internal services, Docker APIs, and monitoring backends are never directly exposed to the public internet.

- [DefectDojo Github](https://github.com/DefectDojo/django-DefectDojo)
- [DefectDojo Docs](https://docs.defectdojo.com/get_started/about/about_defectdojo/)

## Target architecture

The public side of the deployment should be small:
```
Internet
  |
  | HTTP/HTTPS
  v
Public reverse proxy / DefectDojo NGINX
  |
  v
DefectDojo web application
```


The private administrative side should use VPN:
```
Admin workstation
  |
  | Tailscale or WireGuard
  v
VM private VPN interface
  |
  +--> Dockhand
  +--> Grafana
  ```

The internal service side should stay inside Docker networks:
```
DefectDojo application services
  |
  +--> PostgreSQL
  +--> Valkey
  +--> Celery worker
  +--> Celery beat
  +--> initializer job
```

The public IP must not expose PostgreSQL, Valkey, Celery, Prometheus, Grafana, Loki, cAdvisor, Node Exporter, Dockhand, the Docker socket, or the Docker API.

## Required final result

At the end of the challenge, the deployment must satisfy the following conditions:
- DefectDojo Web interface is reachable publicly
- DefectDojo authentication is enabled.
- Default or generated admin credentials are changed.
- Dockhand is reachable only through the VPN.
- Grafana is reachable only through the VPN.
- Prometheus, Loki, cAdvisor, Node Exporter, and other monitoring components are not public.
- PostgreSQL is internal only.
- Valkey is internal only.
- Celery services are internal only.
- No service exposes the Docker socket directly except a controlled Docker socket proxy if Dockhand requires it.
- Containers are hardened using the checklist from this course.
- Secrets are not committed to Git.
- Image scanning and SBOM evidence are produced.
- Host and container monitoring are deployed.

## Starting point

You will start from the deployment in the `deployment` directory. Run the starting deployment:
```bash
# Move to the deployment directory
cd ~/containerized_infrastructure_and_workload_security/05_Defend_The_Flag/deployment
# Make the script executable
chmod +x generate_deployment.sh
# Run the script to generate the deployment
./generate_deployment.sh

# Start the deployment with Docker Compose
sudo docker compose up

# Stop the deployment when done
sudo docker compose down -v
```

Before hardening anything, bring the default stack up and understand it. Do not blindly copy production settings from the internet. The starting Compose file is a useful baseline, but the final solution must be customized.

## Checklist suggestions
- Define the public and private access model
- Configure TLS and the public reverse proxy
- Deploy VPN for administration (Tailscale or WireGuard)
- Segment Docker networks
- Harden DefectDojo containers
- Add runtime and behavior monitoring
- Handle Dockhand safely
- Handle Grafana and observability safely
- Protect secrets

## Required submission

Submit the zip file of the deployment directory with the following contents:
- The `docker-compose.yaml` file with the final deployment configuration.
- `generate_deployment.sh` script to generate the deployment and all necessary configuration files from templates and environment variables.
- A `README.md` file with deployment instructions and notes on the hardening steps taken.
- `.env.example` file with environment variables for the deployment.
- Any additional configuration files needed for the deployment (e.g., NGINX config, VPN config, monitoring config).
