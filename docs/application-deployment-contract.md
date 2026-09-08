# Section 7 — Application deployment contract and image delivery

**2026-09-09 — Ready for review (design + infra foundation prepared; not deployed).** No deployment, no application source access, no live changes, no commit or push. This document is the interface between this infrastructure repository and the application repository, reconciled against the application repository's Human-accepted initial scaffold. It keeps three kinds of statement distinct: **accepted infrastructure decisions (A)**, **proposed application contract defaults (B)**, and **application-owned open fields (C)**. Accepted context: the [Section 5 application architecture](application-architecture.md) is Human accepted (service boundaries, networks, storage/secrets model, canonical hostname, containerized TLS). Nothing here authorizes deployment.

## Confirmed application runtime facts

The separate application repository has completed and accepted its initial scaffold. The following application runtime facts are now **confirmed** and replace the corresponding B defaults and C open fields:

| Fact | Confirmed value |
|---|---|
| Target platform | `linux/arm64` |
| Frontend internal port | `3000` |
| API internal port | `3001` |
| `/api/*` ownership | API (NestJS) |
| Readiness endpoint (frontend and API) | `GET /health/ready` |
| Runtime UID:GID | `10001:10001` |
| State | frontend and API are stateless/disposable; no persistent application filesystem is currently required |
| Process model | foreground processes; graceful `SIGTERM`; no in-container supervisor |
| Migrations | reuse the API image and execute `prisma migrate deploy` |
| Database | PostgreSQL 18 |

Real production GHCR image references/digests are **not** available yet and must not be invented; deployment cannot proceed against placeholder images.

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

## B. Proposed application contract defaults (now reconciled)

Defaults confirmed by the application are marked **Confirmed**; the remainder are infra-owned or still open (see C).

| Field | Recommended default | Status |
|---|---|---|
| Frontend internal port | `3000` | Confirmed |
| API internal port | `3001` | Confirmed |
| Readiness | `GET /health/ready` (frontend local; API after an authenticated DB query) | Confirmed — exact API probe body still open (C.1) |
| Runtime user | non-root UID/GID `10001:10001`, drop capabilities, no-new-privileges | Confirmed |
| `/api` ownership | NestJS owns `/api` and `/api/*` (prefix preserved); Next.js must not compete | Confirmed |
| Service / network names | `frontend`/`api`/`db`/`migrate`/`proxy`/`certbot` on `app`/`db`/`edge` | Infra-owned |
| Restart / init | `unless-stopped` long-running; `init: true` frontend/api; `"no"` migrate | Infra-owned |
| Health cadence | 10 s interval, 3 s timeout, 5 failures, start 30 s (60 s API) | Infra-owned (tune after cold starts) |

## C. Application-owned open fields (reconciled)

These values are supplied by the application project and are not invented by infrastructure. They block executable Compose work until provided.

### C.1 Awaiting application implementation

1. Real `WEB_IMAGE` and `API_IMAGE` GHCR references pinned by immutable digest (`…@sha256:…`).
2. Exact nonsecret environment variable names and the database connection layout (host/user/name, and how the password file is consumed).
3. Exact file-based secret names and confirmation of `*_FILE`-style reading support.
4. Exact writable runtime paths (frontend cache/tmp; API tmp), given the confirmed stateless default.
5. Exact API readiness semantics (the authenticated DB query and expected schema).

### C.2 Product-dependent, still unresolved

6. Egress requirements — whether any server-side outbound Internet is needed (none initially).
7. Persistent storage beyond PostgreSQL (e.g. uploads) — none required now; revisit only if uploads are approved.
8. Additional secrets (e.g. session-signing key, sandbox provider keys) and their exact names.

## Image delivery model (recommended initial)

- **Registry:** GHCR (private packages, read-only deploy tokens, multi-arch capable).
- **Build:** GitHub Actions + Buildx producing `linux/arm64` images; prefer native arm64 runners, QEMU emulation as a CI fallback.
- **Architecture:** ARM64-only is sufficient initially (one ARM64 host, ARM64 developer machines); multi-arch only if an amd64 path appears later.
- **Immutability:** release version + git SHA tags for traceability, but deployment pins by digest in `images.env`.
- **Server authentication:** a read-only registry credential (PAT scoped to `packages:read`) used only at pull time and stored host-only, never mounted into containers or committed.
- **No server builds; no floating tags** (`:latest`) anywhere in the deploy path.

## Compose contract skeleton (proposed — not implemented)

The concrete infra-side Compose model is prepared in [`../deploy/compose.yaml`](../deploy/compose.yaml) (review only; image references are supplied externally via `images.env` and not yet available). The abstract contract:

| Service | Image | Networks | Published ports | Mounts / secrets | Lifecycle / ordering |
|---|---|---|---|---|---|
| `proxy` | Nginx (pinned) | `edge`, `app` | `0.0.0.0:80`/`443` | release `nginx.conf`/`conf.d`; `letsencrypt` ro; `acme_webroot` ro; `staging_access` secret | `unless-stopped`; starts independent of upstreams |
| `frontend` | `${WEB_IMAGE}` | `app` | none | no secrets; ephemeral `/tmp` | `unless-stopped`, `init: true`, UID 10001 |
| `api` | `${API_IMAGE}` | `app`, `db` | none | `db_app_password`, `session_signing_key` | `unless-stopped`, `init: true`, UID 10001; `depends_on: db (service_healthy)` |
| `db` | PostgreSQL 18 (digest to be pinned) | `db` | none | `pg_data` → `/var/lib/postgresql`; init role files | `unless-stopped`; `pg_isready` |
| `migrate` | `${API_IMAGE}` | `db` | none | `db_migration_password` | `restart: "no"`, profile `tools`; `prisma migrate deploy` exit 0 gate |
| `certbot` | certbot (pinned) | `edge` | none | `letsencrypt` rw, `acme_webroot` rw, bounded tmpfs | `unless-stopped` loop |

- **Nginx routing:** `/` and assets → `frontend:3000`; `/api` and `/api/` → `api:3001` (prefix preserved). Ports are confirmed.
- **Release ordering:** DB healthy → run the migration job to exit 0 → start API/frontend → verify the full request path through the proxy.
- All services inherit the accepted Docker `local` log policy (10m × 3, compressed). No `container_name`, host network, privileged mode, Docker socket, or host PID namespace.
