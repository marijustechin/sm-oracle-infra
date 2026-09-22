# sm-oracle-infra TODO

## How to use this roadmap

Items are unfinished planned work, not approved architectural decisions or authorization to execute. Use an explicitly scoped task under [AGENTS.md](AGENTS.md); repository work does not authorize live changes. Resolve decisions and prerequisites before dependent execution. Read-only tasks do not update this roadmap unless requested.

Necessary manual server changes must be documented, with reproducible scripts/configuration added where practical. Implemented and verified items are removed in the reviewable diff and recorded in [CHANGELOG.md](CHANGELOG.md); this does not imply human acceptance.

## 7. Deployment

The [application deployment contract](docs/application-deployment-contract.md) is reconciled against the application's confirmed runtime facts (ports 3000/3001, `/health/ready`, UID 10001, stateless + graceful SIGTERM, `prisma migrate deploy`, PostgreSQL 18). The infra-side foundation is in [deploy/](deploy/) and [docs/deployment.md](docs/deployment.md). The application is **deployed and verified** (D-002, 2026-09-15) — see [docs/server.md](docs/server.md#d-002-first-staging-deployment-verified--2026-09-15--ready-for-review).

- [x] Obtain real `WEB_IMAGE`/`API_IMAGE` GHCR digests (contract C.1) and reconcile the exact environment/file-secret names, writable paths and DB connection layout — done 2026-09-15; digests recorded in the contract ("Published application images")
- [x] Update `deploy/compose.yaml` to the reconciled interface: grant `jwt_access_secret` (replacing `session_signing_key`) as `JWT_ACCESS_SECRET_FILE`, and provide `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER` plus `DB_PASSWORD_FILE` to both `api` and `migrate` — done 2026-09-15; `postgres:18` pinned by digest; db init grants fixed and validated locally
- [x] Host-side image pull and `linux/arm64` verification with the real digests (packages are public; no server registry credential required) — done 2026-09-15
- [x] Verify Prisma/ORM compatibility with PostgreSQL 18 — verified live 2026-09-15 (migration exit 0, idempotent)
- [x] Provision the staging secrets (root-managed files under `/etc/sokoladas-staging/secrets/`) — done 2026-09-15 (values not recorded; ownership/mode verified). Recovery custody/rotation confirmation remains open
- [x] Execute deployment (`deploy/deploy.sh deploy`) and verify frontend/API health through Nginx end-to-end — done 2026-09-15
- [ ] Confirm secret recovery custody/rotation procedure
- [ ] Deploy staging transactional email (SMTP). Repository wiring is prepared (2026-09-18): `api` receives the `SMTP_*`/`MAIL_FROM` group from `deploy/smtp.env` (host-only template `smtp.env.example`), the password is the root-managed `smtp_password` file secret (app UID 10001, 0400) mounted as `SMTP_PASSWORD_FILE`, and `api` joins the outbound-only `egress` network (no published ports; `app`/`db` remain internal). Remaining: provide the staging `smtp.env` values and secret file, add the provider's DNS/SPF/DKIM authorization, and deploy under a separately authorized task. Application side is implemented and locally real-email-verified (`smshop/docs/email.md`); contract C.2.6/8
- [ ] Invited staging access: the reviewed `nginx.conf` currently has the `auth_basic` gate disabled, so the application is publicly reachable. Decide whether to enable the invited-access gate; uploads/payments remain disabled (SMTP enablement is tracked above)
- [ ] Verify clean deploy from scratch and test rollback with explicit migration-rollback limitations
- [ ] Create a deployment user/process if unattended deployment is ever wanted (currently human sudo only)
- [ ] Deployment hardening (ARCH-004): manifest-driven `deploy.sh release`, host applied-release state (`applied.json`), explicit previous-release selection for rollback, richer health checks and retained deployment evidence. The preparatory release metadata (build manifest, approved release manifest, `images.env` resolver) is in place.

**D-002 (first staging deployment) — DONE 2026-09-15 (Ready for review, not Human accepted).** Root task: `../tasks/done/D-002-first-oracle-staging-deployment.md`. Remaining items above are follow-ups, not deployment blockers.

## 8. Backups

Resolve applicable backup needs before introducing valuable persistent data. Demo status does not establish disposability.

- [ ] Decide which data can be recreated and which must be backed up
- [ ] Choose backup destination and cadence
- [ ] Define PostgreSQL backup strategy
- [ ] Define media/uploads backup strategy
- [ ] Store backups outside Oracle VM
- [ ] Define retention policy
- [ ] Test restore procedure

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
