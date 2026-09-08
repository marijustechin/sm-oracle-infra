# sm-oracle-infra TODO

## How to use this roadmap

Items are unfinished planned work, not approved architectural decisions or authorization to execute. Use an explicitly scoped task under [AGENTS.md](AGENTS.md); repository work does not authorize live changes. Resolve decisions and prerequisites before dependent execution. Read-only tasks do not update this roadmap unless requested.

Necessary manual server changes must be documented, with reproducible scripts/configuration added where practical. Implemented and verified items are removed in the reviewable diff and recorded in [CHANGELOG.md](CHANGELOG.md); this does not imply human acceptance.

The six-file documentation baseline and basic secret-handling rules are Human accepted. Section 5 architecture is [Human accepted](docs/application-architecture.md) and closed; operational implementation and secret delivery remain open below. The [recorded inventory](docs/server.md) distinguishes historical reports from unverified current state.

## 4. Docker host

Docker Engine, Compose and Buildx are installed and verified [Human accepted](docs/server.md#docker-host-installed-and-verified--2026-09-08--human-accepted). The approved sudo administration model, default storage locations, bounded local logging and restart guidance are recorded. No application or test containers/images remain. Installation is complete; future deployment exposure verification remains:

- [ ] Verify container forwarding/NAT and Docker-published ports with OCI rules for the actual deployment; keep direct application/database ports private. Recheck after any authorized firewall reload/reboot before claiming persistence.

## 6. Domain and HTTPS

- [ ] Confirm the application /api routing contract under approved canonical `sokoladas.eu`
- [ ] Decide dynamic versus reserved addressing and verify relevant existing DNS before changes
- [ ] Point the chosen hostname(s) to the authorized OCI address after those decisions
- [ ] Implement the accepted Nginx/Certbot container workflow with hourly certificate checks; include certificate persistence, bootstrap and approved apex/www redirects
- [ ] At web deployment, separately approve and verify TCP 80/443 ingress across OCI and the host/container path; keep UDP 443 and TCP/UDP 111 outside public policy
- [ ] Enable HTTPS
- [ ] Verify HTTP -> HTTPS redirect
- [ ] Verify certificate renewal

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
