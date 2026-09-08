# sm-oracle-infra TODO

## How to use this roadmap

Items are unfinished planned work, not approved architectural decisions or authorization to execute. Use an explicitly scoped task under [AGENTS.md](AGENTS.md); repository work does not authorize live changes. Resolve decisions and prerequisites before dependent execution. Read-only tasks do not update this roadmap unless requested.

Necessary manual server changes must be documented, with reproducible scripts/configuration added where practical. Implemented and verified items are removed in the reviewable diff and recorded in [CHANGELOG.md](CHANGELOG.md); this does not imply human acceptance.

## 7. Deployment

The [application deployment contract](docs/application-deployment-contract.md) defines the interface to the application repository, the recommended image delivery model (GHCR + GitHub Actions buildx, ARM64-only, digest-pinned), and the blockers that must be resolved first. The items below remain unfinished until the application supplies the §5 answers.

- [ ] Implement the accepted prebuilt ARM64 image delivery model; select registry/build environment and verify image access/pins
- [ ] Obtain application image contracts: ports, /api ownership, health/migration commands, UIDs, write paths and file-secret support
- [ ] Verify PG18 compatibility with selected ORM/extensions before initialization
- [ ] Implement Compose services, accepted edge/app/db networks, persistent volumes, initialization and health checks
- [ ] Provision per-service secrets, confirm recovery custody and verify access/rotation
- [ ] Implement and verify invited staging access and disabled uploads/email/payments; separately approve any integration and required egress
- [ ] Create deployment user/process if needed
- [ ] Add deploy script
- [ ] Add rollback procedure
- [ ] Verify clean deploy from scratch

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
