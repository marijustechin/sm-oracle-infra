# sm-oracle-infra TODO

## How to use this roadmap

Items are unfinished planned work, not approved architectural decisions or authorization to execute. Use an explicitly scoped task under [AGENTS.md](AGENTS.md); repository work does not authorize live changes. Resolve decisions and prerequisites before dependent execution. Read-only tasks do not update this roadmap unless requested.

Necessary manual server changes must be documented, with reproducible scripts/configuration added where practical. Implemented and verified items are removed in the reviewable diff and recorded in [CHANGELOG.md](CHANGELOG.md); this does not imply human acceptance.

The six-file documentation baseline and basic secret-handling rules are Human accepted. Operational secret delivery remains open below. The [recorded inventory](docs/server.md) distinguishes historical reports from unverified current state.

## 4. Docker host

Docker Engine, Compose and Buildx are installed and verified [Human accepted](docs/server.md#docker-host-installed-and-verified--2026-09-08--human-accepted). The approved sudo administration model, default storage locations, bounded local logging and restart guidance are recorded. No application or test containers/images remain. Installation is complete; future deployment exposure verification remains:

- [ ] Verify container forwarding/NAT and Docker-published ports with OCI rules for the actual deployment; keep direct application/database ports private. Recheck after any authorized firewall reload/reboot before claiming persistence.

## 5. Demo application architecture

- [ ] Define services:
  - [ ] frontend
  - [ ] API
  - [ ] PostgreSQL
  - [ ] reverse proxy
- [ ] Define Docker networks
- [ ] Define persistent volumes
- [ ] Decide secret storage/delivery/access/rotation/recovery and environment configuration before deploying services needing secrets
- [ ] Add health checks
- [ ] Decide staging audience/access, demo data, outbound email, and payment sandbox behavior before enabling applicable capabilities

## 6. Domain and HTTPS

- [ ] Decide root domain vs `demo.sokoladas.eu` and API naming
- [ ] Decide dynamic versus reserved addressing and verify relevant existing DNS before changes
- [ ] Point the chosen hostname(s) to the authorized OCI address after those decisions
- [ ] Choose Caddy or Nginx before installing/configuring the reverse proxy
- [ ] At web deployment, separately approve and verify TCP 80/443 ingress across OCI and the host/container path; keep UDP 443 and TCP/UDP 111 outside public policy
- [ ] Enable HTTPS
- [ ] Verify HTTP -> HTTPS redirect
- [ ] Verify certificate renewal

## 7. Deployment

- [ ] Define deployment strategy
- [ ] Decide whether server pulls from GitHub or CI pushes
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
