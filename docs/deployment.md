# Section 7 — Deployment foundation (secrets, registry, PostgreSQL, rollback)

**2026-09-15 — Deployed and verified (D-002).** The first staging deployment to `sokoladas-demo` is live and verified; see [server.md](server.md#d-002-first-staging-deployment-verified--2026-09-15--ready-for-review) and [CHANGELOG.md](../CHANGELOG.md). This document records the infra-side mechanisms (secrets, registry, PostgreSQL, rollback) alongside [`deploy/compose.yaml`](../deploy/compose.yaml), [`deploy/deploy.sh`](../deploy/deploy.sh), [`deploy/images.env.example`](../deploy/images.env.example), [`deploy/proxy/nginx.conf`](../deploy/proxy/nginx.conf) and [`deploy/db/init/`](../deploy/db/init/). The reconcilable contract lives in [application-deployment-contract.md](application-deployment-contract.md).

## Image pins (WEB_IMAGE / API_IMAGE)

- Deployment images are supplied externally via `images.env` (`WEB_IMAGE`, `API_IMAGE`), copied from [`images.env.example`](../deploy/images.env.example) and kept outside Git.
- `deploy.sh validate` **refuses any value that is not `image@sha256:…`**, so mutable tags cannot become production pins.
- Nginx and Certbot digests are pinned in `deploy/compose.yaml` (already verified `linux/arm64` in Section 6). PostgreSQL is pinned by digest in `deploy/compose.yaml` (`postgres@sha256:4ef4db…`); Prisma/ORM compatibility with PostgreSQL 18 was verified in D-001.
- The application packages are public on GHCR, so no server-side registry credential is required; the host still needs docker/sudo to pull.

## Release manifests and images.env generation

Deployment metadata is prepared in three distinct layers — **desired** release,
**applied** release, and deployment **evidence**. See
[`deploy/releases/README.md`](../deploy/releases/README.md) for the schemas.

- **Build manifest** — the `smshop` `Images` workflow emits a non-secret,
  machine-readable `release-manifest` artifact describing what was built:
  `schemaVersion`, `createdAt`, source repository/commit/ref, the images run id
  and the immutable `@sha256:` web/API references. It carries no deployment
  state, feature flags, configuration values or secrets.
- **Approved staging release manifest** — the operator copies the build manifest
  and adds a staging `releaseId`, the expected infra contract commit, and
  optional notes, committing it as `deploy/releases/<release-id>.json`
  (non-secret). `deploy/releases/example-release.json` is an illustrative,
  never-applied example.
- **Host applied state** — what actually ran on the host (implemented
  `applied.json`; ARCH-004); never committed.

`images.env` is generated deterministically from the approved manifest and stays
host-only/git-ignored:

```sh
python3 scripts/resolve_release_manifest.py deploy/releases/<release-id>.json --out images.env
```

The resolver accepts only immutable `@sha256:` references and writes exactly
`WEB_IMAGE=…` and `API_IMAGE=…`. Mutable tags, malformed references, missing
image entries and unexpected schema versions are rejected (tests:
`scripts/tests/test_resolve_release_manifest.py`). This is metadata preparation
only; it does not deploy and performs no network access.

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
| `turnstile_secret_key` | `api` | Cloudflare Turnstile backend secret (`TURNSTILE_SECRET_KEY_FILE`) | app UID 10001, 0400 |
| `google_client_secret` | `api` | Google OAuth client secret (`GOOGLE_CLIENT_SECRET_FILE`) | app UID 10001, 0400 |
| `staging_access` | `proxy` | htpasswd hash file for the invited-access gate | Nginx worker UID, 0400 |

- The parent directory is `root:root 0700`. The `db_init_*` copies exist because PostgreSQL's init scripts run as the database OS user, not root; both copies must be kept synchronized during rotation.
- No secret value is generated in this task; the model and ownership are recorded, not the material.

## Turnstile configuration (public build-time + private host-only)

Cloudflare Turnstile spans build-time and runtime configuration:

- **Public site key (build-time).** `NEXT_PUBLIC_TURNSTILE_SITE_KEY` is inlined
  into the **web** image by the `smshop` `Images` workflow, which supplies it as a
  Docker build argument from a GitHub Actions repository variable (never a
  secret). Changing it requires rebuilding the web image. See
  `smshop/docs/deployment.md`.
- **Private secret (host-only, runtime).** The backend secret is the root-managed
  file `/etc/sokoladas-staging/secrets/turnstile_secret_key` (owner app UID
  `10001`, mode `0400`), mounted read-only and consumed by the `api` service as
  `TURNSTILE_SECRET_KEY_FILE=/run/secrets/turnstile_secret_key`. It is never
  rendered into an environment value, never committed, and never placed in
  GitHub Actions.

When the secret file is present and readable, the API enforces the challenge on
the protected auth endpoints and fails closed; when it is absent the feature is
disabled. The value is never logged or captured in evidence.

## Google OAuth enablement

Google OAuth is an optional, all-or-none application group (`GOOGLE_CLIENT_ID`,
`GOOGLE_CLIENT_SECRET`, `GOOGLE_CALLBACK_URL`); when the whole group is absent
the API reports `google:false` and the frontend hides the Google action
(`GET /api/auth/capabilities`). The application behaviour is unchanged; this is
staging configuration only.

- **Nonsecret config (host-only):** `deploy/google.env` (template
  `deploy/google.env.example`) supplies `GOOGLE_CLIENT_ID` (the public web client
  ID) and `GOOGLE_CALLBACK_URL`
  (`https://sokoladas.eu/api/auth/google/callback`, which must match the Google
  Cloud OAuth client's Authorized redirect URI exactly). `deploy.sh` sources it
  and `compose.yaml` requires both, so a release cannot render a partial Google
  configuration.
- **Client secret (host-only):** the root-managed file
  `/etc/sokoladas-staging/secrets/google_client_secret` (owner app UID `10001`,
  mode `0400`), mounted read-only and consumed as
  `GOOGLE_CLIENT_SECRET_FILE=/run/secrets/google_client_secret`. Never committed,
  never in GitHub Actions or release manifests.
- **No web rebuild required:** the frontend learns Google availability at runtime
  from the capability endpoint, so enabling Google reuses the deployed images.

## SMTP enablement and API egress

Transactional email is an approved API outbound integration. The application
implements the provider-independent SMTP interface (`smshop/docs/email.md`); the
infrastructure side was deployed with D-004 (`d004-v2`, 2026-09-22; see
[server.md](server.md)).

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

## Persistent product media (D-006)

Uploaded product images are stored on a persistent named volume so they survive
container replacement and redeploys.

- `media_data` (`sokoladas-staging_media_data`) is mounted at
  `/var/lib/sokoladas-media` on the `api` service, with
  `MEDIA_STORAGE_DIR=/var/lib/sokoladas-media`. The API writes normalized WebP
  files under `products/` and serves them at the app-relative
  `/media/products/<uuid>.webp` path stored on catalogue products.
- Docker creates named volumes root-owned, but the API runs as UID 10001. A
  one-shot `media-init` service (root, profile `tools`) creates
  `<MEDIA_STORAGE_DIR>/products` and chowns it to `10001:10001`. `deploy.sh
  release` runs it after migrations and before starting `api`/`frontend`.
- `location /media/` in the proxy is routed to the API upstream; only the proxy
  still publishes `80/443`.
- The volume is not touched by `rollback` (which recreates only `frontend`/`api`)
  or by any destructive command; `deploy.sh` contains no volume-deletion command.
- Catalogue content is imported after deployment with
  [`deploy/catalog-import/`](../deploy/catalog-import/README.md) (idempotent, slug-keyed);
  media files are copied into the volume with UID 10001 ownership.

## Scoped unattended deployment access (2026-10-07, extended 2026-10-07)

The `deploy` host account no longer has `NOPASSWD:ALL`. It may run only the
root-owned entry point `/usr/local/sbin/sokoladas-deploy`
(`deploy ALL=(root) NOPASSWD: /usr/local/sbin/sokoladas-deploy`), which supports
`status`, `stage <id>`, `release <id>` and `rollback <id|previous>`. The source
and install steps live in [`deploy/entrypoint/`](../deploy/entrypoint/README.md).

- The entry point discards the caller environment (`env -i`; `Defaults:deploy
  !setenv`), validates the release id and resolved path, requires the whole
  release tree (compose, proxy, db init, certbot, env files, manifest) to be
  root-owned and not group/other writable, and validates the manifest (schema,
  matching release id, allowed project GHCR repositories, immutable `@sha256:`
  digests, `linux/arm64`, 40-hex source commit, and rejection of unsupported
  fields). It never runs a shell, editor, `docker`, or `systemctl` for the
  caller, and the account is not in the `docker` group.
- `stage` builds a release directory from the versioned root-owned template at
  `/opt/sokoladas-staging/template` and the non-secret host-env at
  `/etc/sokoladas-staging/hostenv`; it accepts only a bounded JSON manifest on
  stdin, pull no images and changes nothing running. An existing release id is
  idempotent when the content is identical and is refused when it differs.
- `release`/`rollback` map to the established manifest-driven `deploy.sh release`
  / `rollback`; rollback still only restores images and does not reverse schema
  migrations. Migration ordering and the forward-only guarantee are unchanged.
- `stage`, `release` and `rollback` share one root-owned lock
  (`/opt/sokoladas-staging/state/deploy.lock`).
- Recovery is independent: `ubuntu` retains SSH and passwordless sudo, and an
  administrator can always run `sudo ./deploy.sh release <id>` directly.
  Unrestricted `deploy` sudo is never restored. Template refreshes are the only
  administrator operation ordinary releases may need.

Unattended commands:

```sh
ssh deploy@sokoladas.eu 'sudo -n /usr/local/sbin/sokoladas-deploy stage <release-id>' < manifest.json
ssh deploy@sokoladas.eu 'sudo -n /usr/local/sbin/sokoladas-deploy release <release-id>'
ssh deploy@sokoladas.eu 'sudo -n /usr/local/sbin/sokoladas-deploy status'
ssh deploy@sokoladas.eu 'sudo -n /usr/local/sbin/sokoladas-deploy rollback previous'
```

Since 2026-10-08 (H-015) the application CI also invokes this entry point for
automatic staging deployment: after its required checks and image publication
succeed, the `smshop` workflow stages the release manifest produced by the same
run (stdin) and runs `release`/`status` as the `deploy` account, using a dedicated
least-privilege SSH key held in the GitHub `staging` environment. The server-side
lock and this entry point are unchanged; see `smshop/docs/deployment.md` and
`docs/application-deployment-contract.md`.

A release staged before a `deploy.sh` fix is repaired in place with the narrowly
scoped administrator tool, which replaces only `deploy.sh` and verifies nothing
else changes:

```sh
sudo deploy/entrypoint/install-release-script.sh <release-id>
```


## Migration ordering and rollback limitations

- Order: start `db` → wait `service_healthy` → run the one-shot `migrate` (`prisma migrate deploy`) to exit 0 → start `api`/`frontend` → activate the app-routing proxy → verify.
- The migration job reuses the API image and exits 0 only on success; a non-zero exit aborts deployment.
- **Application image rollback is not database rollback.** `deploy.sh rollback` restores an explicitly approved previous release and recreates only `frontend`/`api`; it does **not** revert migrations and never runs destructive database actions. A destructive or incompatible migration requires a reviewed repair or restore path (backups are Section 8). Do not claim the database is automatically safe merely because images roll back.

## Manifest-driven release workflow (ARCH-004)

Model C is implemented around the existing Compose stack. Nothing here contacts
GitHub, adds SSH automation, or introduces a privileged agent.

Operator flow:

```text
CI publishes build manifest  ->  human approves a release manifest
  -> operator SSHes to the host
  -> sudo sokoladas-deploy stage <release-id>   (manifest on stdin;
       validate manifest -> build root-owned release dir from the trusted template)
  -> sudo sokoladas-deploy release <release-id>
       validate manifest -> stage images.env -> validate compose
       -> pull images -> db healthy -> migrate (explicit) -> api/frontend
       -> proxy/certbot -> health/smoke -> applied state -> evidence
```

- **Manifest resolution.** `release <release-id>` loads
  `releases/<release-id>.json` (relative to the release dir; override with
  `SOKOLADAS_MANIFEST_DIR`), validates `schemaVersion`, the release id,
  `source.commit`, immutable `@sha256:` refs and the `linux/arm64` platform, then
  deterministically generates the host-only `images.env`.
- **Applied state (host-only, never committed).**
  `/opt/sokoladas-staging/state/applied.json` records the actual applied release:
  `releaseId`, `appliedAt`, `appliedBy`, source commit, exact web/API digest refs,
  infra commit and `previousReleaseId`. It is written atomically **only after** a
  successful deploy and health checks; a failed deployment is never marked
  applied. History copies are kept under `state/history/`.
- **Rollback.** `sudo ./deploy.sh rollback previous` restores the previous
  successfully applied release; `sudo ./deploy.sh rollback <release-id>` restores
  an explicit approved release. It recreates only `frontend`/`api`, never touches
  the database or volumes, fails closed when no target is recorded, and warns
  that the schema is not reverted.
- **Health/smoke.** Non-destructive: `compose ps`, internal proxy/frontend/API
  readiness, an only-the-proxy-publishes assertion, and public read-only checks
  (apex `200`, `www` and HTTP redirects, ACME path, unauthenticated
  `/api/auth/me` `401`). Public checks can be skipped in dry contexts with
  `SOKOLADAS_SKIP_PUBLIC=1`. No data is created.
- **Evidence (host-only, non-secret).**
  `/opt/sokoladas-staging/evidence/<timestamp>-<release-id>/` retains the
  manifest, generated `images.env`, compose/migration/health logs and a
  `summary.txt` (`finalStatus: success|failure`). Failed deployments retain
  evidence too. No secrets, cookies or tokens are captured.
- **Failure behavior:** manifest/compose/preflight failures abort before any live
  change; image-pull failure leaves the running release untouched; migration
  failure aborts before starting the new application services; health failure
  exits nonzero without writing applied state and prints the rollback command.

`deploy.sh deploy` remains as a legacy direct deploy using the current
`images.env` (no applied-state tracking); prefer `release`. Helper tests live in
`scripts/tests/test_deploy_release.sh`.

## D-006 verification status (2026-10-07)

Release **`d006-v1`** deployed and verified (see [CHANGELOG](../CHANGELOG.md)).
Source `9069715`; Images run `37669495907`; web `sha256:5e68f161…`, api
`sha256:8699cf87…` (`linux/arm64`).

- `applied.json` → `d006-v1` (`previousReleaseId: d005-v1`); evidence
  `finalStatus: success`.
- Migrations applied: `add_user_roles`, `add_product_catalogue_and_shop`,
  `add_catalogue_tags_and_legacy_ratings`.
- Persistent `media_data` volume created; `media-init` chowned it; nginx
  `/media/` route live.
- Catalogue import: 5 products, `tortai` category, 9 tags, verified legacy
  ratings; 5 images in the volume.
- Public: homepage/branding `200`; `/tortai` + 5 detail pages `200`; public API
  shows tags/ratings and no commercial fields; `/media/products/…` `200
  image/webp`; deletes/redirects/`X-Robots-Tag` and invited-access gate
  unchanged; only the proxy publishes `80/443`.
- Admin: authorized access (temporary signed token), image upload and public
  serving verified, then the test upload and temporary admin were removed.
- Limitations: Always Free eligibility not verifiable (no OCI account access);
  interactive login not exercised (Turnstile enforced, no browser);
  pixel-level responsive screenshots not captured (no browser).

## D-005 verification status (2026-09-22)

Configuration-only release **`d005-v1`** deployed and verified (see
[CHANGELOG](../CHANGELOG.md) and the
[server inventory](server.md#d-005-google-oauth-enabled-verified--2026-09-22--ready-for-review)).
Reuses the d004-v2 application images (no rebuild).

- `applied.json` → `d005-v1` (`previousReleaseId: d004-v2`); evidence
  `finalStatus: success`; migration no pending.
- `/api/auth/capabilities` → `{"google":true}`; the Google start endpoint 302s
  with `redirect_uri=https://sokoladas.eu/api/auth/google/callback`.
- Google OAuth smoke and credentials/Turnstile/SMTP regression passed (human).
- Only the proxy publishes `80/443`.

## D-004 verification status (2026-09-22)

Corrective release **`d004-v2`** deployed and verified (see
[CHANGELOG](../CHANGELOG.md) and the
[server inventory](server.md#d-004-corrective-release-d004-v2-verified--2026-09-22--ready-for-review)).
`d004-v1` was superseded by the Turnstile site-key fix.

- Manifest-driven `deploy.sh release d004-v2`; `applied.json` → `d004-v2`
  (`previousReleaseId: d004-v1`); evidence `finalStatus: success`.
- Migration reported no pending migrations (schema unchanged).
- Only the proxy publishes `80/443`; frontend/API/PostgreSQL remain private.
- Public: apex `200`, HTTP→HTTPS `308`, www→apex `308`, `/health/ready` `200`,
  unauthenticated `/api/auth/me` `401`, ACME probe `404`.
- Turnstile renders with no `400020` (corrected public site key); API enforces the
  challenge. SMTP (Resend) real-email/auth smoke passed (human).

## D-004 verification status (d004-v1, superseded) (2026-09-22)

`d004-v1` deployed 2026-09-22 but was superseded by the corrective `d004-v2`
(Turnstile site-key fix). Its applied state and evidence remain recorded.

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

> 2026-10-08 annotation: this D-002 record is historical. Ordinary releases now run through the scoped, root-owned `/usr/local/sbin/sokoladas-deploy` entry point (`stage`/`release`/`rollback`); see "Scoped unattended deployment access" above.
