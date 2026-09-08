# Section 7 — Deployment foundation (secrets, registry, PostgreSQL, rollback)

**2026-09-09 — Ready for review (foundation only; not deployed).** No application images or production secrets exist yet; nothing here is executed. This records the infra-side mechanisms prepared alongside [`deploy/compose.yaml`](../deploy/compose.yaml), [`deploy/deploy.sh`](../deploy/deploy.sh), [`deploy/images.env.example`](../deploy/images.env.example), [`deploy/proxy/nginx.conf`](../deploy/proxy/nginx.conf) and [`deploy/db/init/`](../deploy/db/init/). The reconcilable contract lives in [application-deployment-contract.md](application-deployment-contract.md).

## Image pins (WEB_IMAGE / API_IMAGE)

- Deployment images are supplied externally via `images.env` (`WEB_IMAGE`, `API_IMAGE`), copied from [`images.env.example`](../deploy/images.env.example) and kept outside Git.
- `deploy.sh validate` **refuses any value that is not `image@sha256:…`**, so mutable tags cannot become production pins.
- Nginx and Certbot digests are pinned in `deploy/compose.yaml` (already verified `linux/arm64` in Section 6). PostgreSQL uses the `postgres:18` tag as a placeholder; its digest is pinned only after Prisma/ORM compatibility is verified (TODO §7).

## GHCR authentication (no credentials committed)

- The server authenticates to GHCR with a **read-only** token scoped to `packages:read`, used only at pull time.
- The credential lives host-only (e.g. `/root/.docker/config.json` via `docker login ghcr.io`), is never committed, never mounted into containers, and never shared with the application CI.
- If the application images are public, no server-side credential is needed; if private, the token is the minimal read-only grant. Prefer OIDC/CI-issued tokens where the platform supports them.

## Secret delivery structure and permissions

Secrets are root-managed files under `/etc/sokoladas-staging/secrets/` (outside Git), mounted as file-backed Compose secrets at the documented targets. The accepted Section 5 names are used as the infra-side model; the exact application-side consumption (env mapping, `*_FILE` support) remains an open contract field (C.1.3/C.1.4).

| Secret | Consumers | Purpose | File ownership (accepted model) |
|---|---|---|---|
| `db_admin_password` | `db` | PostgreSQL bootstrap superuser | postgres image UID, 0400 |
| `db_app_password` | `db` (init), `api` | application DB login | app UID 10001, 0400 |
| `db_migration_password` | `db` (init), `migrate` | schema/migration login | app UID 10001, 0400 |
| `db_init_app_password` | `db` (init only) | init-script copy of the app password | postgres image UID, 0400 |
| `db_init_migration_password` | `db` (init only) | init-script copy of the migration password | postgres image UID, 0400 |
| `session_signing_key` | `api` | staging session/signing material | app UID 10001, 0400 |
| `staging_access` | `proxy` | htpasswd hash file for the invited-access gate | Nginx worker UID, 0400 |

- The parent directory is `root:root 0700`. The `db_init_*` copies exist because PostgreSQL's init scripts run as the database OS user, not root; both copies must be kept synchronized during rotation.
- No secret value is generated in this task; the model and ownership are recorded, not the material.

## PostgreSQL 18 runtime and persistence

- `db` runs `postgres:18` on the internal `db` network with no published ports; `pg_data` (`sokoladas-staging_pg_data`) is mounted at `/var/lib/postgresql`.
- Bootstrap uses `POSTGRES_PASSWORD_FILE=/run/secrets/db_admin_password`; the `db_init_*` secrets feed the first-boot role script.
- The first-boot script creates the application and migration roles with **placeholder names** (`sokoladas_app`, `sokoladas_migration`) that are provisional/application-owned; **schema creation and grants are owned by the application migration** (`prisma migrate deploy`), not by infra. The final role names, database name and grants must come from the application contract before first initialization.
- **Prisma/ORM compatibility with PostgreSQL 18 remains unverified** and must be confirmed before first initialization or any irreversible data.

## Migration ordering and rollback limitations

- Order: start `db` → wait `service_healthy` → run the one-shot `migrate` (`prisma migrate deploy`) to exit 0 → start `api`/`frontend` → activate the app-routing proxy → verify.
- The migration job reuses the API image and exits 0 only on success; a non-zero exit aborts deployment.
- **Application image rollback is not database rollback.** `deploy.sh rollback` re-selects the previous known-good digests and recreates `frontend`/`api`, but does **not** revert migrations. A destructive or incompatible migration requires a reviewed repair or restore path (backups are Section 8). Do not claim the database is automatically safe merely because images roll back.

## Verification boundaries (cannot yet be verified)

Until real digests, secrets and the application schema exist, the following remain unverified and are **not** claimed:

- Real `linux/arm64` application image pull.
- Real application startup and graceful shutdown.
- Migration execution against the actual application schema.
- Frontend/API health through Nginx end-to-end.
- A clean deployment from scratch.
- Final application/database public-port isolation after deployment.

Only repository-local validation has been performed (Compose parsing, shell syntax, whitespace/secret scans). No live server change is authorized by this document.
