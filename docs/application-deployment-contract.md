# Section 7 — Application deployment contract and image delivery

**2026-09-09 — Ready for review (design + infra foundation).** **2026-09-15: the contract has been implemented and the first staging deployment is live and verified (D-002; see [server.md](server.md#d-002-first-staging-deployment-verified--2026-09-15--ready-for-review)).** **2026-09-22: the manifest-driven D-004 release is deployed and verified; the current applied release is the corrective `d004-v2` (see [server.md](server.md#d-004-corrective-release-d004-v2-verified--2026-09-22--ready-for-review)).** No live change is authorized by this document itself.

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
| Healthcheck tooling | `wget`, `grep`, `cat`, `awk`, `sha256sum` are present in both runtime images (alpine/busybox); the Compose health commands work as written |
| Runtime user | both images run as UID:GID `10001:10001`; verified |
| Migration runtime | the API image contains the Prisma CLI and the built `@smshop/db` package; its default working directory is `/app/packages/db`, so `prisma migrate deploy` resolves `prisma7.config.ts` and the schema; verified exit 0 against PostgreSQL 18 as UID 10001 |
| Database connection | a full `DATABASE_URL` (or `DATABASE_URL_FILE`) wins; otherwise the application assembles the URL from `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER` and `DB_PASSWORD` (or `DB_PASSWORD_FILE`). The API and the Prisma CLI use the same resolution |
| Access-token secret | application secret is `JWT_ACCESS_SECRET` (supports `JWT_ACCESS_SECRET_FILE`); there is no `session_signing_key` variable in the application |

Real production GHCR image references/digests now exist (first publication 2026-09-15; see "Published application images" below). On 2026-09-15 the application repository built and ran both images locally for `linux/arm64`, then published them via GitHub Actions to GHCR; the published digests were pulled back and re-verified.

### Published application images — 2026-09-15

First immutable application images published by the application repository's
`Images` workflow (GitHub Actions run `35013479067`, source commit
`d515dff20390b76cb4b82e68838d78e38d318f2e`). Deployment must reference these by
digest; `deploy/images.env` supplies them at deploy time (the file stays outside
Git).

| Image | Reference (immutable) | Platform |
|---|---|---|
| Web (`WEB_IMAGE`) | `ghcr.io/marijustechin/smshop-web@sha256:ca5855625acd8ef51f41e9b688511ab7f9ffa55f892c232c370ab30b8a728220` | `linux/arm64` |
| API (`API_IMAGE`) | `ghcr.io/marijustechin/smshop-api@sha256:eab3ee009a5c086bfd94df9230f34133ec7111a9f1f122a1649b20c43368c7ed` | `linux/arm64` |

Source SHA tag (traceability, not the deploy reference):
`sha-d515dff20390b76cb4b82e68838d78e38d318f2e`.

Verification performed 2026-09-15 against these exact digests: both are
`linux/arm64` (no `amd64` entry); pulled from GHCR and run under emulation; web
and API `/health/ready` returned `200`; `prisma migrate deploy` from the
published API image exited `0` against PostgreSQL 18; registration returned
`201`. The digests are the deployment pin; the SHA tag is traceability only.

### Superseded application images — 2026-09-22 (not deployed)

A pair of immutable `linux/arm64` images published by the application
repository's `Images` workflow (run `35754237865`, source commit
`070e68076c875c737e928d76703baf1b0d80bd9f`, CI run `35754237630` green) was
**never applied** to staging. The D-004 line of releases used the later `64cb8c6`
source instead:
- run `35764280629` **attempt 2** (web `sha256:506ea172…`, api `sha256:25c14d80…`)
  was applied as `d004-v1` and then superseded by the corrective `d004-v2`;
- run `35764280629` **attempt 3** (web `sha256:b6f3936f…`, api `sha256:b5ce59a6…`)
  is the current `d004-v2` release (corrected Turnstile public site key).

| Image | Reference (immutable) | Platform |
|---|---|---|
| Web (`WEB_IMAGE`) | `ghcr.io/marijustechin/smshop-web@sha256:74e39c382a0d44cd5bee0ee17f454c2b9f0b9b63bb6bccf916ae508b3d57bf19` | `linux/arm64` |
| API (`API_IMAGE`) | `ghcr.io/marijustechin/smshop-api@sha256:e92294ad9c199f78030a170b476d2fc795fcbe6ace4de53049568da344dbe378` | `linux/arm64` |

Source SHA tag (traceability, not the deploy reference):
`sha-070e68076c875c737e928d76703baf1b0d80bd9f`.

### Build/release metadata (ARCH-003 / ARCH-004)

The application repository's `Images` workflow publishes a non-secret build
manifest artifact (`release-manifest`) carrying the immutable `@sha256:` web/API
references and the source commit. Infrastructure consumes an **approved staging
release manifest** (`deploy/releases/<release-id>.json`, non-secret), validates it
(immutable digests, `linux/arm64`, schema version) and generates the host-only
`images.env`; `deploy.sh release <release-id>` then applies it and records
host-only applied state and deployment evidence (`docs/deployment.md`). The build
manifest never contains deployment state; applied state and evidence are host-only
and never committed.

### Reconciled application runtime interface — 2026-09-15

Application-owned names/semantics (authoritative detail in
`smshop/docs/configuration.md` and `smshop/docs/deployment.md`). This section
records the interface only; it does not invent secret values.

**Runtime (nonsecret) environment**

| Variable | Service | Notes |
|---|---|---|
| `NODE_ENV=production` | api | required for `Secure` refresh cookies |
| `PORT` | api | `3001` |
| `WEB_ORIGIN` | api | `https://sokoladas.eu` (CORS + email links) |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` | api, migrate | nonsecret DB components; port defaults `5432` |
| `JWT_ACCESS_TTL`, `AUTH_SESSION_TTL` | api | optional; defaults `15m`/`7d` |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`, `MAIL_FROM` | api | nonsecret SMTP group; supplied via `deploy/smtp.env` (host-only) |
| Google/Turnstile blocks | api | optional; all-or-none groups, disabled when absent |

**File-backed secrets** (`<NAME>_FILE`, raw value; one trailing newline tolerated)

| Variable | Consumer | Purpose |
|---|---|---|
| `DB_PASSWORD_FILE` (or `DATABASE_URL_FILE`) | api | application DB login |
| `DB_PASSWORD_FILE` (or `DATABASE_URL_FILE`) | migrate | migration DB login (separate role) |
| `JWT_ACCESS_SECRET_FILE` | api | signs access JWTs and derives the OAuth transaction key |
| `SMTP_PASSWORD_FILE` | api | SMTP login password (staging secret file `smtp_password`) |
| `GOOGLE_CLIENT_SECRET_FILE` | api | optional |
| `TURNSTILE_SECRET_KEY_FILE` | api | Cloudflare Turnstile backend secret (staging secret file `turnstile_secret_key`); optional, enables challenge enforcement when present |

**Frontend (build-time, public, inlined by Next.js)**

| Variable | Notes |
|---|---|
| `NEXT_PUBLIC_API_BASE_URL` | unset in production; relative `/api` is used (same origin) |
| `NEXT_PUBLIC_TURNSTILE_SITE_KEY` | required at image build time only when Turnstile is enabled |

**Migration job** (`migrate`, reusing `API_IMAGE`): command
`prisma migrate deploy`, default working directory `/app/packages/db`, runs as
UID 10001, exit 0 required.

Infrastructure-side changes implied by this reconciliation (implementation
follow-ups recorded in `TODO.md` §7): replace the `session_signing_key` secret
with `jwt_access_secret`; supply the DB component variables and
`DB_PASSWORD_FILE` (or a `DATABASE_URL` file) to `api` and `migrate` instead of
assembling the URL inside Compose; keep the existing `db_*` init secrets.

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

This file is the **single authoritative deployment contract**. The application
repository keeps no local copy and reads this document from the parent
workspace's `sm-oracle-infra` for cross-repository context. Document ownership
does not give infrastructure unilateral ownership of application-side
decisions: the application repository supplies its own runtime
requirements/facts (the application-owned C fields below), while this
repository records and consumes the reconciled deployment interface.

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

1. Real `WEB_IMAGE` and `API_IMAGE` GHCR references pinned by immutable digest
   (`…@sha256:…`) — **resolved 2026-09-15**. `ghcr.io/marijustechin/smshop-web`
   and `ghcr.io/marijustechin/smshop-api` are published and pinned by digest
   (see "Published application images" above); both verified `linux/arm64`.
2. Exact nonsecret environment variable names and the database connection
   layout — **resolved**. A full `DATABASE_URL`/`DATABASE_URL_FILE` wins;
   otherwise the application assembles the URL from `DB_HOST`/`DB_PORT`/
   `DB_NAME`/`DB_USER` plus `DB_PASSWORD`/`DB_PASSWORD_FILE`.
3. Exact file-based secret names and `*_FILE` reading support — **resolved**
   application-side: `DB_PASSWORD_FILE` (or `DATABASE_URL_FILE`),
   `JWT_ACCESS_SECRET_FILE`, `SMTP_PASSWORD_FILE`,
   `GOOGLE_CLIENT_SECRET_FILE`, `TURNSTILE_SECRET_KEY_FILE`. Production secret
   file names/mounts remain infrastructure-owned.
4. Exact writable runtime paths — **resolved**: ephemeral `/tmp`; the images are
   otherwise stateless (verified runs performed no other filesystem writes).
5. Exact API readiness semantics — **resolved**: `GET /health/ready` performs an
   authenticated `SELECT 1` through the application Prisma client and returns
   `200 {status:'ok'}` or `503` when the database is unavailable. It does not
   verify full schema completeness.

### C.2 Product-dependent, still unresolved

6. Egress requirements — SMTP (transactional email) is the first concrete
   integration that needs server-side outbound Internet. The accepted
   architecture gives the API **no initial outbound access** (`app`/`db` are
   internal); the dedicated, outbound-only `egress` network is **prepared in
   `deploy/compose.yaml`** (only `api` attached; no ports published). No other
   egress is required today. See "Staging SMTP enablement" below.
7. Persistent storage beyond PostgreSQL (e.g. uploads) — none required now; revisit only if uploads are approved.
8. Additional secrets beyond `JWT_ACCESS_SECRET` / DB credentials — the SMTP
   password is the next concrete secret (see below); sandbox payment or other
   provider keys remain undefined.

### Staging SMTP enablement (infra wiring prepared 2026-09-18 — not deployed)

The application implements the provider-independent SMTP interface
(`smshop/docs/email.md`); the real local flow was verified against the
administrator's SMTP account (registration/verification/resend/password
recovery). The staging infrastructure wiring is prepared in this repository:

- the nonsecret `SMTP_HOST` / `SMTP_PORT` / `SMTP_SECURE` / `SMTP_USER` /
  `MAIL_FROM` values are supplied via `deploy/smtp.env` (host-only, git-ignored;
  template `deploy/smtp.env.example`), interpolated into the `api` service as
  required `${VAR:?…}` values;
- the password is the root-managed `smtp_password` secret file under
  `/etc/sokoladas-staging/secrets/` owned by app UID `10001` mode `0400`, mounted
  as `SMTP_PASSWORD_FILE` (same model as `jwt_access_secret`);
- the API joins the outbound-only `egress` network in `deploy/compose.yaml`
  (bridge, not internal; no published ports; only `api` attached). `app`/`db`
  remain internal, PostgreSQL stays private, and only the proxy publishes
  `80`/`443`;
- the security implication is recorded in `docs/deployment.md`: the API gains
  unrestricted outbound Internet (no per-provider allowlist).

Remaining before live email: provide the staging provider values + secret file,
add the provider's DNS/SPF/DKIM authorization, and deploy under a separate
authorized task. Tracked in `TODO.md` §7. No SMTP credential value is recorded
here.

## Image delivery model (recommended initial)

- **Registry:** GHCR (private packages, read-only deploy tokens, multi-arch capable).
- **Build:** GitHub Actions + Buildx producing `linux/arm64` images; prefer native arm64 runners, QEMU emulation as a CI fallback.
- **Architecture:** ARM64-only is sufficient initially (one ARM64 host, ARM64 developer machines); multi-arch only if an amd64 path appears later.
- **Immutability:** release version + git SHA tags for traceability, but deployment pins by digest in `images.env`.
- **Server authentication:** a read-only registry credential (PAT scoped to `packages:read`) used only at pull time and stored host-only, never mounted into containers or committed.
- **No server builds; no floating tags** (`:latest`) anywhere in the deploy path.

## Compose contract skeleton (proposed — not implemented)

The concrete infra-side Compose model is prepared in [`../deploy/compose.yaml`](../deploy/compose.yaml) (image references are supplied externally via `images.env` as immutable `@sha256:` digests). The abstract contract:

| Service | Image | Networks | Published ports | Mounts / secrets | Lifecycle / ordering |
|---|---|---|---|---|---|
| `proxy` | Nginx (pinned) | `edge`, `app` | `0.0.0.0:80`/`443` | release `nginx.conf`/`conf.d`; `letsencrypt` ro; `acme_webroot` ro; `staging_access` secret | `unless-stopped`; starts independent of upstreams |
| `frontend` | `${WEB_IMAGE}` | `app` | none | no secrets; ephemeral `/tmp` | `unless-stopped`, `init: true`, UID 10001 |
| `api` | `${API_IMAGE}` | `app`, `db` | none | `db_app_password` (as `DB_PASSWORD_FILE`), `jwt_access_secret` (as `JWT_ACCESS_SECRET_FILE`) | `unless-stopped`, `init: true`, UID 10001; `depends_on: db (service_healthy)` |
| `db` | PostgreSQL 18 (digest-pinned) | `db` | none | `pg_data` → `/var/lib/postgresql`; init role files | `unless-stopped`; `pg_isready` |
| `migrate` | `${API_IMAGE}` | `db` | none | `db_migration_password` (as `DB_PASSWORD_FILE`) | `restart: "no"`, profile `tools`; `prisma migrate deploy` exit 0 gate |
| `certbot` | certbot (pinned) | `edge` | none | `letsencrypt` rw, `acme_webroot` rw, bounded tmpfs | `unless-stopped` loop |

- **Nginx routing:** `/` and assets → `frontend:3000`; `/api` and `/api/` → `api:3001` (prefix preserved). Ports are confirmed.
- **Release ordering:** DB healthy → run the migration job to exit 0 → start API/frontend → verify the full request path through the proxy.
- All services inherit the accepted Docker `local` log policy (10m × 3, compressed). No `container_name`, host network, privileged mode, Docker socket, or host PID namespace.

**Infrastructure implementation status (D-002, 2026-09-15):** the `deploy/compose.yaml` env/secret wiring matches the reconciled interface — `api` receives `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER=sokoladas_app` with `DB_PASSWORD_FILE` and `JWT_ACCESS_SECRET_FILE`; `migrate` receives the same components with `DB_USER=sokoladas_migration` and `DB_PASSWORD_FILE`; `session_signing_key` was replaced by `jwt_access_secret`; `postgres` is pinned by digest; and `db/init` grants the migration role schema DDL and the runtime role DML only. The first staging deployment is **live and verified** (release `/opt/sokoladas-staging/releases/d002-v1`). **2026-09-22: the manifest-driven D-004 releases are deployed and verified; the current applied release is the corrective `d004-v2`** (source `64cb8c6`; web `sha256:b6f3936f…`, api `sha256:b5ce59a6…`; `d004-v1` web `sha256:506ea172…`/api `sha256:25c14d80…` superseded; Turnstile secret wired via `TURNSTILE_SECRET_KEY_FILE`; SMTP/Resend configured); see [server.md](server.md#d-004-corrective-release-d004-v2-verified--2026-09-22--ready-for-review).
