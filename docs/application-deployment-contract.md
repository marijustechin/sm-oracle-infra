# Section 7 — Application deployment contract and image delivery

**2026-09-08 — Ready for review (design only).** No deployment, no application source access, no live changes, no commit or push. This document is the interface between this infrastructure repository and the future application repository. It keeps three kinds of statement distinct: **accepted infrastructure decisions (A)**, **proposed application contract defaults (B)**, and **application-owned open fields (C)**. Accepted context: the [Section 5 application architecture](application-architecture.md) is Human accepted (service boundaries, networks, storage/secrets model, canonical hostname, containerized TLS). Nothing here authorizes deployment.

## Ownership and boundary

| Repository | Owns |
|---|---|
| Application repository | Source code (Next.js/NestJS), Dockerfiles, Prisma schema/migrations, application health implementation and tests, and production image builds (CI) |
| `sm-oracle-infra` (this repo) | Compose/runtime configuration, image digest pins, Nginx routing, PostgreSQL runtime, production secret provisioning, deployment and rollback procedures, server-side verification |

Boundary rules:

- The infrastructure does not access or modify application source and does not write application code.
- Application CI **builds and publishes** images, but does **not** receive production SSH credentials and does **not** automatically deploy to the Oracle host in the initial model.
- Deployment to the Oracle host is a deliberate, reviewed action performed from the infrastructure side against digest-pinned images.
- The application never publishes its own host ports; only the infrastructure-owned proxy publishes 80/443.

## A. Accepted infrastructure decisions

These are fixed and already accepted:

- **Registry:** GitHub Container Registry (GHCR).
- **Build:** GitHub Actions with Buildx.
- **Architecture:** prebuilt `linux/arm64` application images.
- **No application builds on the Oracle host** (no source checkout, no Node.js/pnpm on the host).
- **Deployment by immutable OCI digest** (`images.env` pins `image@sha256:…`).
- **Networking:** the accepted `edge` / `app` / `db` model (internal-only `app` and `db`; proxy on `edge`).
- **TLS:** Nginx terminates TLS for `https://sokoladas.eu`; plain HTTP inside the container networks.
- **PostgreSQL:** the runtime is owned by infrastructure (PostgreSQL 18 container, `pg_isready` health gate).
- **Secrets:** file-based secret delivery via per-service mounts.
- **Exposure:** no direct public publication of frontend/API/PostgreSQL; only the proxy publishes 80/443.

## B. Proposed application contract defaults (recommended — not final facts)

These are the infrastructure's recommended defaults. They become binding only when the application project accepts them, or supplies its own values (see C). They must not be read as final application facts.

| Field | Recommended default |
|---|---|
| Frontend internal port | `3000` |
| API internal port | `3001` |
| Frontend readiness | `GET /health/ready` → 200 (no DB/API dependency) |
| API readiness | `GET /health/ready` → 200 after an authenticated DB query; 503 otherwise |
| Runtime user | non-root, UID/GID `10001:10001`, drop capabilities, no-new-privileges |
| `/api` ownership | NestJS owns `/api` and `/api/*` (prefix preserved); Next.js must not compete |
| Service / network names | `frontend`/`api`/`db`/`migrate`/`proxy`/`certbot` on `app`/`db`/`edge` |
| Restart / init | `unless-stopped` for long-running services; `init: true` for frontend/api; `"no"` for migrate |
| Health cadence | 10 s interval, 3 s timeout, 5 failures, start period 30 s (60 s API) |

## C. Application-owned open fields (explicit application-project inputs)

These values are supplied by the application project and are not invented by infrastructure. They block executable Compose work until provided.

1. Exact frontend and API image references (digests) and confirmation of `linux/arm64`.
2. The migration command and its success semantics (exit 0 on success).
3. Actual environment variable names and the database connection layout (host/user/name and how the password file is consumed).
4. Actual file-based secret names and confirmation of file-reading support.
5. Writable runtime paths (frontend cache/tmp; API tmp; uploads only if later approved).
6. Persistent-storage requirements beyond PostgreSQL (and optional uploads).
7. Egress requirements (any server-side outbound Internet).
8. Graceful-shutdown / signal-handling confirmation.
9. Confirmation of the B defaults (ports, health paths, UID) or the application's alternative values.

## Image delivery model (recommended initial)

- **Registry:** GHCR (private packages, read-only deploy tokens, multi-arch capable).
- **Build:** GitHub Actions + Buildx producing `linux/arm64` images; prefer native arm64 runners, QEMU emulation as a CI fallback.
- **Architecture:** ARM64-only is sufficient initially (one ARM64 host, ARM64 developer machines); multi-arch only if an amd64 path appears later.
- **Immutability:** release version + git SHA tags for traceability, but deployment pins by digest in `images.env`.
- **Server authentication:** a read-only registry credential (PAT scoped to `packages:read`) used only at pull time and stored host-only, never mounted into containers or committed.
- **No server builds; no floating tags** (`:latest`) anywhere in the deploy path.

## Compose contract skeleton (proposed — not implemented)

| Service | Image | Networks | Published ports | Mounts / secrets | Lifecycle / ordering |
|---|---|---|---|---|---|
| `proxy` | Nginx (pinned) | `edge`, `app` | `0.0.0.0:80`/`443` | release `nginx.conf`/`conf.d`; `letsencrypt` ro; `acme_webroot` ro; `staging_access` secret | `unless-stopped`; starts independent of upstreams |
| `frontend` | frontend image | `app` | none | no secrets; ephemeral `/tmp` + declared cache path | `unless-stopped`, `init: true` |
| `api` | API image | `app`, `db` | none | `db_app_password`, `session_signing_key`; uploads only if approved | `unless-stopped`, `init: true`; `depends_on: db (service_healthy)` |
| `db` | PostgreSQL 18 (pinned) | `db` | none | `pg_data` → `/var/lib/postgresql`; init role files | `unless-stopped`; `pg_isready` |
| `migrate` | same digest as `api` | `db` | none | `db_migration_password` | `restart: "no"`, profile `tools`; exit 0 gate |
| `certbot` | certbot (pinned) | `edge` | none | `letsencrypt` rw, `acme_webroot` rw, bounded tmpfs | `unless-stopped` loop |

- **Nginx routing:** `/` and assets → `frontend:<frontend port default>`; `/api` and `/api/` → `api:<api port default>` (prefix preserved). Ports are the B defaults until the application confirms them.
- **Release ordering:** DB healthy → run the migration job to exit 0 → start API/frontend → verify the full request path through the proxy.
- All services inherit the accepted Docker `local` log policy (10m × 3, compressed). No `container_name`, host network, privileged mode, Docker socket, or host PID namespace.
