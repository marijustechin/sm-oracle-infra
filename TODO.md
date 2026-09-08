# sm-oracle-infra TODO

## How to use this roadmap

Items are unfinished planned work, not approved architectural decisions or authorization to execute. Use an explicitly scoped task under [AGENTS.md](AGENTS.md); repository work does not authorize live changes. Resolve decisions and prerequisites before dependent execution. Read-only tasks do not update this roadmap unless requested.

Necessary manual server changes must be documented, with reproducible scripts/configuration added where practical. Implemented and verified items are removed in the reviewable diff and recorded in [CHANGELOG.md](CHANGELOG.md); this does not imply human acceptance.

## 7. Deployment

The [application deployment contract](docs/application-deployment-contract.md) is reconciled against the application's confirmed runtime facts (ports 3000/3001, `/health/ready`, UID 10001, stateless + graceful SIGTERM, `prisma migrate deploy`, PostgreSQL 18). The infra-side foundation is prepared for review in [deploy/](deploy/) and [docs/deployment.md](docs/deployment.md): Compose model, digest-pin mechanism (`images.env`), deploy/rollback script, secret-delivery model, PostgreSQL runtime, and proxy app routing. Real GHCR image digests and production secrets do not exist yet.

- [ ] Obtain real `WEB_IMAGE`/`API_IMAGE` GHCR digests and confirm exact environment/file-secret names, writable paths and DB connection layout (contract C.1)
- [ ] Set up GHCR registry/build access and verify `linux/arm64` pull with the real digests
- [ ] Verify Prisma/ORM compatibility with PostgreSQL 18 before initialization
- [ ] Provision real production secrets (root-managed files) and confirm recovery custody/rotation
- [ ] Create deployment user/process if needed
- [ ] Implement and verify invited staging access and disabled uploads/email/payments; separately approve any integration and required egress
- [ ] Execute deployment (`deploy/deploy.sh deploy`) and verify frontend/API health through Nginx end-to-end
- [ ] Verify clean deploy from scratch and test rollback with explicit migration-rollback limitations

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
