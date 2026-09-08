# sm-oracle-infra TODO

## How to use this roadmap

Items are unfinished planned work, not approved architectural decisions or authorization to execute. Use an explicitly scoped task under [AGENTS.md](AGENTS.md); repository work does not authorize live changes. Resolve decisions and prerequisites before dependent execution. Read-only tasks do not update this roadmap unless requested.

Necessary manual server changes must be documented, with reproducible scripts/configuration added where practical. Implemented and verified items are removed in the reviewable diff and recorded in [CHANGELOG.md](CHANGELOG.md); this does not imply human acceptance.

The six-file documentation baseline and basic secret-handling rules are Human accepted. Section 5 architecture is [Human accepted](docs/application-architecture.md) and closed; operational implementation and secret delivery remain open below. The [recorded inventory](docs/server.md) distinguishes historical reports from unverified current state.

## 4. Docker host

Docker Engine, Compose and Buildx are installed and verified [Human accepted](docs/server.md#docker-host-installed-and-verified--2026-09-08--human-accepted). The approved sudo administration model, default storage locations, bounded local logging and restart guidance are recorded. The Docker installation test was cleaned up; Section 6 now runs the Nginx HTTP bootstrap. Installation is complete; future deployment exposure verification remains:

- [ ] Verify container forwarding/NAT and Docker-published ports with OCI rules for the actual deployment; keep direct application/database ports private. Recheck after any authorized firewall reload/reboot before claiming persistence.

## 6. Domain and HTTPS — Human accepted (closed)

Section 6 is complete and **Human accepted**: reserved public IPv4 (`79.76.117.246`) and DNS, the HTTP bootstrap, staging-CA and production Let's Encrypt issuance, HTTPS activation (canonical apex/www 308 redirects, apex maintenance 503, ACME HTTP-01 preserved), the containerized renewal loop and hourly certificate watcher, the isolated certificate replacement/reload test, and reboot persistence. Evidence and procedures are in the [HTTPS runbook](docs/https-runbook.md) and [inventory](docs/server.md).

Two operational follow-ups are preserved and are **not** Section 6 implementation work: (1) the first real on-schedule Let's Encrypt production renewal before the current certificate expires (2026-12-07), and (2) the reserved OCI public IPv4 pricing/status follow-up (tracked in the README open decisions).

## 7. Deployment

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

## 10. Disaster recovery

- [ ] Decide the rebuild boundary for OCI resource creation
- [ ] Document full rebuild procedure
- [ ] Ensure infra repo contains no secrets
- [ ] Test rebuilding VM from documentation/scripts
- [ ] Test restoring application data
