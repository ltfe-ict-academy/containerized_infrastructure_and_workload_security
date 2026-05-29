# Hands-On: Network Hardening

This version starts from the image-hardened application and changes only the Docker networking layer. The application code and the existing image build approach are intentionally left as they were. The goal here is to make the network shape safer without mixing in runtime hardening, secret management, TLS, monitoring, or authorization controls that belong to later chapters.

The original Compose file was convenient for a lab, but it had a common problem: every service lived on one shared default network and every important service published a port on the host. The browser could reach the frontend, but the host could also reach the backend API, PostgreSQL, and Redis directly. That makes the environment easy to test, but it gives an attacker too many doors.

In this version, the application has one public entry point and several private network segments.

```text
Host / Browser
     |
     | 127.0.0.1:8080 by default
     v
reverse-proxy
  |          |
  |          +-- frontend_net -- frontend
  |
  +-- backend_net -- backend
                     |      |
                     |      +-- cache_net -- redis
                     |
                     +-- db_net ---- db
```

The important change is not the number of networks by itself. The important change is that each service is connected only to the networks it needs.

## What changed

| Area | Before | After |
| --- | --- | --- |
| Host-published ports | `frontend:3000`, `backend:8000`, `db:5432`, `redis:6379` | Only `reverse-proxy:8080` is published |
| Public entry point | Browser called frontend and backend separately | Browser calls one origin: the reverse proxy |
| Backend exposure | Backend API was reachable directly from the host | Backend is reachable only from the reverse proxy and its data networks |
| Database exposure | PostgreSQL was published to the host | PostgreSQL is only on `db_net` |
| Redis exposure | Redis was published to the host | Redis is only on `cache_net` |
| Network layout | One implicit default network | Five explicit networks with clear roles |
| Backend data access | Backend, database, Redis, and frontend shared the same network | Backend has separate paths to database and cache |

## The reverse proxy as the only public door

We added the `reverse-proxy` service because the outside world should not need to know how the internal application is assembled. The browser connects to one address, and Nginx decides where the request goes:

- `/` is forwarded to the frontend service.
- `/api/` is forwarded to the backend service.
- `/healthz` is handled by the proxy itself.

This gives the deployment a single ingress point. That is useful because ingress controls tend to grow over time. Today the proxy only routes requests. Later, the same edge position could be used for TLS termination, request size limits, security headers, rate limiting, authentication checks, or centralized access logging. We are not adding all of those controls in this exercise, because this chapter focuses on Docker networking, but the network layout now gives us a clean place to add them.

The frontend build argument was changed to:

```yaml
VITE_API_BASE_URL: "/api"
```

The frontend no longer needs to call `http://SERVER_IP:8000/api`. The browser calls `/api` on the same origin it used to load the page, and the reverse proxy forwards the request internally. This removes the need to publish the backend API directly to the host.

## Network segmentation

We added explicit Docker networks instead of relying on the single default Compose network.

### `public_net`

Only the reverse proxy joins this network. This is the only service with a host-published port.

```yaml
ports:
  - "${PUBLISH_HOST:-127.0.0.1}:${PUBLIC_PORT:-8080}:8080"
```

The default bind address is `127.0.0.1`, so the lab is reachable from the local host only. If the lab is running on a remote training VM and must be reached from another machine, set `PUBLISH_HOST=0.0.0.0` in `.env` and protect the host with an external firewall or security group. Binding to all interfaces is sometimes necessary in a lab, but it should be an explicit decision.

### `frontend_net`

Only the reverse proxy and the frontend join this network. The frontend does not need access to the database, Redis, or the backend network. It serves static files to the proxy.

### `backend_net`

Only the reverse proxy and the backend join this network. This lets the proxy forward `/api/` traffic to the backend, but it does not give the proxy access to PostgreSQL or Redis.

### `db_net`

Only the backend and PostgreSQL join this network. The database no longer has a host-published port. A local user, a browser, or a container on another network cannot connect to PostgreSQL unless it is deliberately attached to `db_net`.

### `cache_net`

Only the backend and Redis join this network. Redis no longer has a host-published port. This matters because Redis is often deployed as an internal component and should not be treated as an internet-facing service.

## Why we used `internal: true`

The private networks use:

```yaml
internal: true
```

An internal Docker network is created without external connectivity. That is a useful default for data-plane networks such as `db_net` and `cache_net`, because PostgreSQL and Redis do not need to initiate connections to the outside world in this lab. It is also useful for `frontend_net` and `backend_net`, because those networks exist only to connect neighboring application components.

This is not the same as a full network policy engine. Docker Compose does not give us Kubernetes-style allow rules such as “backend may connect only to Redis TCP/6379.” On a Docker bridge network, containers that share the same network can generally reach each other. That is why we kept the networks small. Instead of placing every service on one internal network, we created separate segments so each shared network has a narrow purpose.

## Why we replaced `ports` with `expose` on internal services

The backend, PostgreSQL, Redis, and frontend now use `expose` instead of `ports`.

```yaml
expose:
  - "8000"
```

`expose` documents the port a service listens on for other containers. It does not publish the port on the Docker host. The security improvement comes from the combination of two choices: the port is not published to the host, and the service is attached only to the networks where that service is needed.

This is an important distinction. `EXPOSE` in a Dockerfile and `expose` in Compose are not firewall rules. They are documentation and service metadata. Network isolation comes from the absence of `ports` and from the explicit network membership.

## Running the hardened network example

Copy the `.env.example` to `.env` and adjust the values if needed.

Start the stack:

```bash
sudo docker compose up --build -d
sudo docker compose logs -f
```

Open the application:

```text
http://127.0.0.1:8080
```

Check the backend through the reverse proxy:

```bash
curl http://127.0.0.1:8080/api/health
```

The old direct backend URL should no longer work:

```bash
curl http://127.0.0.1:8000/api/health
```

That failure is expected. The backend is still running, but it is no longer published to the host.

## Verifying the network design

Check the published ports:

```bash
sudo docker compose ps
```

Only `reverse-proxy` should show a host port mapping. The frontend, backend, PostgreSQL, and Redis should not expose host ports.

Inspect the networks:

```bash
sudo docker network inspect example_app_final_public_net

sudo docker network inspect example_app_final_frontend_net

sudo docker network inspect example_app_final_backend_net

sudo docker network inspect example_app_final_db_net

sudo docker network inspect example_app_final_cache_net
```

Expected membership:

| Network | Expected containers |
| --- | --- |
| `example_app_final_public_net` | `reverse-proxy` |
| `example_app_final_frontend_net` | `reverse-proxy`, `frontend` |
| `example_app_final_backend_net` | `reverse-proxy`, `backend` |
| `example_app_final_db_net` | `backend`, `db` |
| `example_app_final_cache_net` | `backend`, `redis` |

Stop the stack when done:

```bash
sudo docker compose down -v
```

## Recap: Docker networking best practices

Use user-defined networks instead of placing everything on Docker's default bridge. A user-defined network gives the Compose project a scoped network and service-name DNS, and it avoids mixing unrelated containers on one broad shared bridge.

Publish only the services that must be reached from outside the Docker host. For a web application, that usually means a reverse proxy or ingress gateway, not the backend API, database, cache, message queue, admin UI, or metrics endpoint.

Bind published ports to the narrowest host address that works. For local labs, `127.0.0.1` is usually enough. Use `0.0.0.0` only when external clients really need access, and pair it with host firewall rules, cloud security groups, or another network perimeter.

Use a reverse proxy as the controlled ingress path. It gives one place to route requests and later add TLS, request limits, logging, authentication, and security headers.

Segment networks by communication path. The frontend does not need the database network. The reverse proxy does not need the cache network. The database and cache do not need the public network.

Use `internal: true` for networks that should not have external connectivity. This is especially useful for databases, caches, queues, and private application-to-application paths.

Remember that a Docker bridge network is not a fine-grained policy engine. If two containers share a bridge network, assume they can reach each other's listening ports. Keep shared networks small and purpose-specific.

Use `expose` for internal service documentation, but do not treat it as a security boundary. The real boundary is whether the service is published with `ports` and which networks the service joins.

Avoid `network_mode: host` for application containers unless there is a strong reason. Host networking removes much of Docker's normal network namespace separation and makes the container share the host network stack.

Do not expose the Docker daemon over TCP, and do not mount the Docker socket into network-facing containers. Access to the Docker API can become control over the host.

Use service names instead of hard-coded container IP addresses. Docker can recreate containers with new IP addresses, while service names remain stable inside the Compose network.

Inspect the live state, not only the YAML. Use `docker compose ps`, `docker compose port`, `docker network inspect`, and host tools such as `ss -lntp` to confirm what is actually reachable.

For multi-host, production, or orchestrated deployments, add stronger controls: Kubernetes NetworkPolicies or CNI policies, eBPF-based enforcement, service mesh authorization, mTLS for service identity, centralized logging, and egress controls. Docker Compose segmentation is a good starting point, but it is not the whole network security program.