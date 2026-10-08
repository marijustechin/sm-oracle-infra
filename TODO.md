# sm-oracle-infra TODO

## How to use this roadmap

Items are unfinished planned work, not approved architectural decisions or authorization to execute. Use an explicitly scoped task under [AGENTS.md](AGENTS.md); repository work does not authorize live changes. Resolve decisions and prerequisites before dependent execution. Read-only tasks do not update this roadmap unless requested.

Necessary manual server changes must be documented, with reproducible scripts/configuration added where practical. Implemented and verified items are removed in the reviewable diff and recorded in [CHANGELOG.md](CHANGELOG.md); this does not imply human acceptance.

## 7. Deployment

The [application deployment contract](docs/application-deployment-contract.md) is reconciled against the application's confirmed runtime facts (ports 3000/3001, `/health/ready`, UID 10001, stateless + graceful SIGTERM, `prisma migrate deploy`, PostgreSQL 18). The infra-side foundation is in [deploy/](deploy/) and [docs/deployment.md](docs/deployment.md). The application is **deployed and verified** — D-002 (2026-09-15), the manifest-driven **D-004** corrective release `d004-v2` (2026-09-22), the **D-006** catalogue + persistent-media release `d006-v1` (2026-10-07) and the **d007-v1** authentication UI polish (2026-10-08, the first release published through the unattended `stage`/`release` pipeline) — see [docs/server.md](docs/server.md#d-007-v1-authentication-ui-polish--deployed-via-the-unattended-pipeline--verified-2026-10-08--ready-for-review).

- [x] Obtain real `WEB_IMAGE`/`API_IMAGE` GHCR digests (contract C.1) and reconcile the exact environment/file-secret names, writable paths and DB connection layout — done 2026-09-15; digests recorded in the contract ("Published application images")
- [x] Update `deploy/compose.yaml` to the reconciled interface: grant `jwt_access_secret` (replacing `session_signing_key`) as `JWT_ACCESS_SECRET_FILE`, and provide `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER` plus `DB_PASSWORD_FILE` to both `api` and `migrate` — done 2026-09-15; `postgres:18` pinned by digest; db init grants fixed and validated locally
- [x] Host-side image pull and `linux/arm64` verification with the real digests (packages are public; no server registry credential required) — done 2026-09-15
- [x] Verify Prisma/ORM compatibility with PostgreSQL 18 — verified live 2026-09-15 (migration exit 0, idempotent)
- [x] Provision the staging secrets (root-managed files under `/etc/sokoladas-staging/secrets/`) — done 2026-09-15 (values not recorded; ownership/mode verified). Recovery custody/rotation confirmation remains open
- [x] Execute deployment (`deploy/deploy.sh deploy`) and verify frontend/API health through Nginx end-to-end — done 2026-09-15
- [ ] Confirm secret recovery custody/rotation procedure
- [x] Deploy staging transactional email (SMTP) — done 2026-09-22 (D-004, `d004-v2`): `api` receives `SMTP_*`/`MAIL_FROM` from host-only `deploy/smtp.env` (Resend), the `smtp_password` file secret (app UID 10001, 0400) mounted as `SMTP_PASSWORD_FILE`, and the outbound-only `egress` network (`app`/`db` internal, no published ports). End-to-end real-email/auth smoke verified (human)
- [x] Enable Turnstile on staging — done 2026-09-22 (D-004): public site key baked into the web image at build time; host-only `turnstile_secret_key` wired into the API via `TURNSTILE_SECRET_KEY_FILE`; the API enforces the challenge (`403 TURNSTILE_REQUIRED` without a token)
- [ ] Invited staging access: the reviewed `nginx.conf` currently has the `auth_basic` gate disabled, so the application is publicly reachable. Decide whether to enable the invited-access gate; uploads/payments remain disabled
- [ ] Verify clean deploy from scratch and test rollback with explicit migration-rollback limitations
- [x] Create a deployment user/process if unattended deployment is ever wanted — done 2026-10-07: dedicated `deploy` host user with non-interactive sudo + docker, used for the `d006-v1` release (unattended deployment remains a human decision per release)
- [x] Harden/scope the `deploy` user's sudo rights if unattended deployment is retained — done 2026-10-07: `NOPASSWD:ALL` replaced by a single root-owned entry point `/usr/local/sbin/sokoladas-deploy` (`status`/`stage`/`release`/`rollback`) with `!setenv`; see `deploy/entrypoint/` and `docs/deployment.md`
- [x] Delegate safe release staging to the `deploy` account — done 2026-10-07: `stage <id>` accepts a bounded JSON manifest on stdin and builds the release directory from the versioned root-owned template (`/opt/sokoladas-staging/template`) and non-secret host-env (`/etc/sokoladas-staging/hostenv`), with atomic install, idempotent/different-content handling and a shared `stage`/`release`/`rollback` lock. Ordinary releases now need no administrator command; template refreshes remain an administrator operation

**D-002 (first staging deployment) — DONE 2026-09-15 (Ready for review, not Human accepted).** Root task: `../tasks/done/D-002-first-oracle-staging-deployment.md`. Remaining items above are follow-ups, not deployment blockers.

**D-004 (updated auth images + staging SMTP/Turnstile) — DONE 2026-09-22; release `d004-v2` (corrective Turnstile site-key fix; `d004-v1` superseded) (Ready for review, not Human accepted).** Root task: `../tasks/done/D-004-deploy-auth-images-and-staging-smtp.md`. Infrastructure/HTTP/Turnstile verified; SMTP/auth smoke verified via Resend.

**D-006 (catalogue + persistent media) — DONE 2026-10-07; current applied release `d006-v1` (Ready for review, not Human accepted).** Root task: `../tasks/done/ORACLE-RELEASE.md`. Added the persistent `media_data` volume + `MEDIA_STORAGE_DIR`/`media-init`, the nginx `/media/` route, and the explicit slug-keyed catalogue import. Migrations applied; 5 catalogue products + images imported; live checks passed (see `docs/server.md`). Pre-deploy DB backup retrieved to the development machine.

## 8. Backups

Resolve applicable backup needs before introducing valuable persistent data. Demo status does not establish disposability.

Implementation is in [`backup/`](backup/) with the design and runbooks in
[docs/backups.md](docs/backups.md). Google authorization is pending; a real
off-server backup and the isolated restore test follow it.

- [x] Decide which data can be recreated and which must be backed up — the database, uploaded media and host secrets/config (incl. the applied release manifest) are backed up; image layers, caches and `pg_data` raw files are not
- [x] Choose backup destination and cadence — Google Drive `atsargines-kopijos/sokoladas` via an rclone `crypt` remote, daily ~03:00 `Europe/Vilnius` (systemd timer)
- [x] Define PostgreSQL backup strategy — consistent `pg_dump -Fc` logical dump, verified in the set
- [x] Define media/uploads backup strategy — `media.tar.gz` of `sokoladas-staging_media_data`; the set fails if a database-referenced media file is missing
- [x] Store backups outside Oracle VM — client-side encrypted (rclone `crypt`) before upload to Drive
- [x] Define retention policy — latest 7 successful daily sets + 4 weekly sets; incomplete sets never deleted; deletion limited to `sokoladas-backups/sets/`
- [ ] Test restore procedure — pending Google authorization and the first off-server backup (`sokoladas-restore-verify run <set>`)


## 9. Monitoring and maintenance

- [ ] Basic disk/RAM/CPU monitoring
- [ ] Container health monitoring
- [ ] Log strategy
- [ ] Security update strategy
- [ ] Disk usage alerts
- [ ] Document routine maintenance
- [ ] Confirm the first real on-schedule Let's Encrypt production renewal succeeds before the certificate expires (2026-12-07); the unattended loop has not yet performed a real renewal
- [ ] Confirm reserved OCI public IPv4 pricing/billing treatment; no spending limit or cost-check cadence is yet in place

## 10. Disaster recovery

- [ ] Decide the rebuild boundary for OCI resource creation
- [ ] Document full rebuild procedure
- [ ] Ensure infra repo contains no secrets
- [ ] Test rebuilding VM from documentation/scripts
- [ ] Test restoring application data
