# Section 7 — Deployment foundation (secrets, registry, PostgreSQL, rollback)

**2026-09-15 — Deployed and verified (D-002).** The first staging deployment to `sokoladas-demo` is live and verified; see [server.md](server.md#d-002-first-staging-deployment-verified--2026-09-15--ready-for-review) and [CHANGELOG.md](../CHANGELOG.md). This document records the infra-side mechanisms (secrets, registry, PostgreSQL, rollback) alongside [`deploy/compose.yaml`](../deploy/compose.yaml), [`deploy/deploy.sh`](../deploy/deploy.sh), [`deploy/images.env.example`](../deploy/images.env.example), [`deploy/proxy/nginx.conf`](../deploy/proxy/nginx.conf) and [`deploy/db/init/`](../deploy/db/init/). The reconcilable contract lives in [application-deployment-contract.md](application-deployment-contract.md).

## Image pins (WEB_IMAGE / API_IMAGE)

- Deployment images are supplied externally via `images.env` (`WEB_IMAGE`, `API_IMAGE`), copied from [`images.env.example`](../deploy/images.env.example) and kept outside Git.
- `deploy.sh validate` **refuses any value that is not `image@sha256:…`**, so mutable tags cannot become production pins.
- Nginx and Certbot digests are pinned in `deploy/compose.yaml` (already verified `linux/arm64` in Section 6). PostgreSQL is pinned by digest in `deploy/compose.yaml` (`postgres@sha256:4ef4db…`); Prisma/ORM compatibility with PostgreSQL 18 was verified in D-001.
- The application packages are public on GHCR, so no server-side registry credential is required; the host still needs docker/sudo to pull.

## GHCR authentication (no credentials committed)

- The server authenticates to GHCR with a **read-only** token scoped to `packages:read`, used only at pull time.
- The credential lives host-only (e.g. `/root/.docker/config.json` via `docker login ghcr.io`), is never committed, never mounted into containers, and never shared with the application CI.
- If the application images are public, no server-side credential is needed; if private, the token is the minimal read-only grant. Prefer OIDC/CI-issued tokens where the platform supports them.

## Secret delivery structure and permissions

Secrets are root-managed files under `/etc/sokoladas-staging/secrets/` (outside Git), mounted as file-backed Compose secrets at the documented targets. The reconciled application-side names (`*_FILE` support) are recorded in the contract; this repository owns the file names, mounts, ownership and rotation.

| Secret | Consumers | Purpose | File ownership (accepted model) |
|---|---|---|---|
| `db_admin_password` | `db` | PostgreSQL bootstrap superuser | postgres image UID, 0400 |
| `db_app_password` | `db` (init), `api` | application DB login | app UID 10001, 0400 |
| `db_migration_password` | `db` (init), `migrate` | schema/migration login | app UID 10001, 0400 |
| `db_init_app_password` | `db` (init only) | init-script copy of the app password | postgres image UID, 0400 |
| `db_init_migration_password` | `db` (init only) | init-script copy of the migration password | postgres image UID, 0400 |
| `jwt_access_secret` | `api` | staging access-token/OAuth-transaction signing material | app UID 10001, 0400 |
| `smtp_password` | `api` | SMTP login password (`SMTP_PASSWORD_FILE`) | app UID 10001, 0400 |
| `staging_access` | `proxy` | htpasswd hash file for the invited-access gate | Nginx worker UID, 0400 |

- The parent directory is `root:root 0700`. The `db_init_*` copies exist because PostgreSQL's init scripts run as the database OS user, not root; both copies must be kept synchronized during rotation.
- No secret value is generated in this task; the model and ownership are recorded, not the material.

## SMTP enablement and API egress

Transactional email is an approved API outbound integration. The application
implements the provider-independent SMTP interface (`smshop/docs/email.md`); the
infrastructure side is prepared here and is **not yet deployed**.

- **Nonsecret settings** (`SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`,
  `MAIL_FROM`) are supplied in `deploy/smtp.env` (host-only, git-ignored; copy
  from `deploy/smtp.env.example`). `compose.yaml` requires them via `${VAR:?…}`
  and `deploy.sh validate` fails if any is missing. They are not stored in
  Compose or Git.
- **Password** is the root-managed file secret `smtp_password`
  (`/etc/sokoladas-staging/secrets/smtp_password`, owner app UID 10001, mode
  `0400`), mounted read-only and consumed as `SMTP_PASSWORD_FILE`. It is never
  placed in Compose, `smtp.env`, or Git.
- **Egress network:** `api` joins the non-internal `egress` bridge network. That
  is the only network change and it gives the API the outbound Internet access
  SMTP requires. No ports are published on `egress`, and only `api` is attached.
- **Inbound isolation is unchanged:** `app` and `db` remain internal; only the
  proxy publishes `80`/`443`; the API, frontend, and PostgreSQL publish nothing.
  PostgreSQL stays on the internal `db` network only.

Security implications of the egress change:

- The API gains **unrestricted outbound** Internet access, not a per-provider
  allowlist. Outbound destinations are not restricted by this change; restricting
  them further would need host/Docker firewall rules (not implemented).
- The API is not reachable inbound through `egress`; only containers attached to
  that network could reach it and none are. No host/public port is added.
- Docker's embedded DNS on `egress` resolves the provider hostname; the API must
  be restarted (recreated) after secret/env changes, since config is read at
  startup.

## PostgreSQL 18 runtime and persistence

- `db` runs the digest-pinned `postgres` image on the internal `db` network with no published ports; `pg_data` (`sokoladas-staging_pg_data`) is mounted at `/var/lib/postgresql`.
- Bootstrap uses `POSTGRES_PASSWORD_FILE=/run/secrets/db_admin_password`; the `db_init_*` secrets feed the first-boot role script.
- The first-boot script creates the application (`sokoladas_app`, runtime) and migration (`sokoladas_migration`, schema owner) roles. It grants the migration role `CREATE, USAGE` on schema `public` and the runtime role `USAGE` only, with default privileges so future migration-created tables/sequences are usable by the runtime role. **Schema creation and grants are owned by the application migration** (`prisma migrate deploy`). This grants gap (PostgreSQL 15+ no longer gives `PUBLIC` CREATE on `public`) was fixed and validated locally against PostgreSQL 18 in D-002 preparation.
- **Prisma/ORM compatibility with PostgreSQL 18 was verified in D-001** (migration and readiness against a disposable PostgreSQL 18); reconfirm during first real initialization.

## Migration ordering and rollback limitations

- Order: start `db` → wait `service_healthy` → run the one-shot `migrate` (`prisma migrate deploy`) to exit 0 → start `api`/`frontend` → activate the app-routing proxy → verify.
- The migration job reuses the API image and exits 0 only on success; a non-zero exit aborts deployment.
- **Application image rollback is not database rollback.** `deploy.sh rollback` re-selects the previous known-good digests and recreates `frontend`/`api`, but does **not** revert migrations. A destructive or incompatible migration requires a reviewed repair or restore path (backups are Section 8). Do not claim the database is automatically safe merely because images roll back.

## Verification status (D-002, 2026-09-15)

Verified live on `sokoladas-demo`:

- Real `linux/arm64` application image pull (web/api digests verified on the host).
- Real application startup; health/readiness on api and frontend.
- Migration execution against the actual application schema (exit 0; idempotent).
- Frontend/API health through Nginx end-to-end; `/api` routing.
- Public-port isolation (only `80/443`; `3000/3001/5432` private).
- Restart/recreate persistence and a repeat deployment.

Still not claimed:

- A forced long database outage to exercise connection-pool reconnection (the D-001 follow-up; it did not reproduce under a `docker restart`).
- A clean deployment from scratch on a fresh host, and a destructive rollback test (schema is forward-only; no down migration).
- Secret recovery custody/rotation.

The live deployment itself was human-executed with interactive sudo; this document records the mechanism and verification, not a standing authorization.
