# sm-oracle-infra

Infrastructure and operational context for the `sokoladas.eu` demo/staging environment of the new `sokoladomeistrai` e-commerce application. This is separate from the current production shop.

Read [AGENTS.md](AGENTS.md) before work. The effective team is Marijus, the owner/developer/administrator, assisted by AI agents. The goal is an inexpensive, understandable, secure, ARM64-compatible environment that can be rebuilt without relying on shell history. OCI Free Tier is the cost objective. Dated human-observed allowance, volume eligibility, and cost evidence is recorded in [docs/server.md](docs/server.md); it does not guarantee future zero charges.

## Working method

Human decision → scoped task → implementation → verification and documentation → Ready for review → human review/corrections → Human accepted → explicitly requested commit.

[AGENTS.md](AGENTS.md) defines these states and authorization boundaries. Repository work does not authorize live changes. Documentation, proposed TODO removal, and change-log updates belong in the reviewable diff; they do not imply human acceptance.

## Intended architecture

The platform direction is a single OCI ARM64 VM with a minimal Ubuntu host, Docker Engine, and Docker Compose. Keep application runtimes and databases in containers. Host software should be limited to administration utilities, Git where needed, Docker, and justified security/backup/monitoring tooling.

The accepted application layout is:

```text
Internet HTTP/HTTPS → chosen DNS hostname → OCI public address
    → container reverse proxy (Nginx)
        → Next.js frontend
        → NestJS API → PostgreSQL
```

Next.js frontend, NestJS API and containerized PostgreSQL are accepted service boundaries; application image contracts remain to be verified. Redis is only a possible internal service, not an approved dependency. Node.js/pnpm belong in application build/runtime containers. Public web traffic enters through the reverse proxy; SSH is a separate administrative service. Intended public ports are 22/tcp, 80/tcp, and 443/tcp; internal application/database ports must remain private. The owner reports verified SSH hardening: public-key authentication enabled, password/keyboard-interactive authentication and direct root login prohibited; evidence is recorded in [docs/server.md](docs/server.md).

The [Section 5 application architecture](docs/application-architecture.md) is **Human accepted** and Section 5 is closed. It defines one Compose project with Nginx, Next.js, NestJS and PostgreSQL plus a Certbot renewal container; edge/app/db networking without initial API Internet access; restricted file secrets; prebuilt ARM64 images; apex/www redirects; and hourly certificate checks. Implementation/provisioning prerequisites remain in TODO Sections 7–8. The application services remain undeployed; Section 6 delivered the HTTP bootstrap and the full HTTPS edge (proxy + Certbot) described below.

The [Section 6 implementation plan](docs/domain-https-plan.md) is complete and Section 6 is **Human accepted and closed**. Reserved IPv4 `79.76.117.246` (`sokoladas-public-ip`) and apex/www DNS are human-verified. The [bootstrap runbook](docs/http-bootstrap-runbook.md) records the Human-accepted HTTP bootstrap; the [HTTPS runbook](docs/https-runbook.md) records the verified certificate/HTTPS work: staging-CA and production Let's Encrypt issuance, HTTPS activation (apex maintenance 503, canonical apex/www 308 redirects, ACME HTTP-01 preserved, only Nginx publishing 80/443), the containerized renewal loop and hourly certificate watcher, an isolated replacement/reload test, and a controlled reboot-persistence test. Two operational follow-ups remain (not implementation blockers): the first real on-schedule Let's Encrypt renewal before the certificate expires (2026-12-07), and the reserved OCI public IPv4 pricing/status follow-up. Pricing/OCI evidence limits are in [docs/server.md](docs/server.md). `sokoladas.online` remains unconfigured.

## Decisions and open questions

This is a lightweight decision record, not an authorization to execute tasks. Baseline directions below were already recorded before the 2026-09-07 documentation remediation and are retained by the approved remediation plan. Their original approval dates/evidence were not recorded; no historical approval is inferred.

| Status / date | Direction or question | Reason / boundary |
|---|---|---|
| Documented baseline / date unrecorded | Demo/staging on OCI ARM64; minimal host; Docker Engine and Compose | Low-cost, reproducible environment; application services in containers |
| Documented baseline / date unrecorded | Keep application source separate; no committed secrets or production customer data | Repository scope and data safety |
| Documented baseline / date unrecorded | Only SSH and web ports intended publicly; private internal service ports | Limit exposure; source restrictions remain open |
| Documented baseline / date unrecorded | Human architectural decisions and review; scoped agent implementation | Marijus remains the decision maker |
| Approved plan / 2026-09-07 | Separate repository/live authorization; explicit approval for destructive/access-breaking actions; lightweight review lifecycle | Remediation plan approved; implementation is Human accepted |
| Owner decision / 2026-09-08 | Canonical HTTPS sokoladas.eu; www permanently redirects to apex; HTTP redirects except ACME HTTP-01 | Planned certificate covers both names; DNS and HTTP bootstrap verified, TLS/redirect activation pending |
| Owner decision / 2026-09-08 | edge: Nginx/Certbot; internal app: Nginx/frontend/API; internal db: API/PostgreSQL/migrate | No initial API Internet access; add dedicated egress only for an actual approved integration |
| Human accepted / 2026-09-08 | Containerized Nginx/Certbot renewal | Hourly certificate-check wrapper accepted; no host renewal timer |
| Human-executed / 2026-09-08 | Reserved public IPv4 79.76.117.246 → primary private IPv4 10.0.0.52 | Resource sokoladas-public-ip; SSH continuity verified by human. DNS now resolves to this reserved address on human evidence; UI lifetime-label inconsistency recorded in docs/server.md |
| Human accepted / 2026-09-08 | Nginx reverse proxy | Administrator familiarity, explicit conventional TLS/proxy configuration and transparency; containerized TLS and hourly checks accepted |
| Human accepted / 2026-09-08 | Nginx + Next.js + NestJS + PostgreSQL in one Compose project | Service boundaries accepted; application artifacts and compatibility still require verification |
| Owner decision / recorded 2026-09-07 | 2 GiB swapfile with swappiness 10; system locale `en_US.UTF-8`, timezone `Europe/Vilnius`; retain package-owned login locale behavior | Human changes/evidence and verification limits in [docs/server.md](docs/server.md); no additional host packages needed now, future installation is requirement-driven |
| Approved / 2026-09-08 | Default Docker/containerd storage on existing ext4; local logs 10m × 3, compression; unless-stopped for future long-running services, no restart for one-shot jobs | Host configuration verified; application networks/volumes and persistence tests remain deployment work |
| Owner decision / recorded 2026-09-07 | marijus primary administrator; ubuntu tested recovery administrator with passwordless sudo; retain opc | Human-reported key-login and forced-command tests in [docs/server.md](docs/server.md); OCI Serial Console recovery independently tested by the owner on 2026-09-07; evidence in docs/server.md |
| Owner decision / recorded 2026-09-07 | SSH port 22; no direct root/password/keyboard-interactive login; public keys enabled; X11 disabled; TCP forwarding enabled | TCP forwarding intentionally supports administrative tunneling; human effective-config and fresh-session checks recorded |
| Owner direction / 2026-09-07 | Retain iptables-nft/netfilter-persistent; no additional UFW; preserve InstanceServices | No firewall change needed now; UDP 123 live-rule consistency is human-verified; historical evidence is preserved in docs/server.md |
| Owner direction / 2026-09-07 | Keep TCP 22 available without a fixed source-IP restriction; do not enable OCI IPv6 | Changing administrator networks; key-only SSH and tested Serial Console. Design IPv6 security before future global addressing |
| Owner direction / 2026-09-07 | Future web ingress TCP 80/443 only, alongside SSH; keep 111 and application/database ports nonpublic | Do not open web ports before the HTTP deployment needs them; Docker exposure requires separate verification |
| Human-executed / recorded 2026-09-07 | rpcbind service and socket disabled and masked; packages retained | Owner reports both units masked/inactive, no port-111 listener, and refused local portmapper query; evidence and limitations in docs/server.md |
| Approved / 2026-09-08 | Rootful Docker from the official Ubuntu repository; administration via sudo, no marijus docker-group membership | Engine, Compose and Buildx verified; no unattended deployment privilege granted. SSH user restrictions remain open |
| Human accepted / 2026-09-08 | Root-managed per-service secret files and owner recovery copies | Provisioning, actual custody and rotation verification remain deployment prerequisites |
| Human accepted / 2026-09-08 | Prebuilt ARM64 images, initial human sudo deployment | Registry/build environment, application contracts, CI and rollback implementation remain unfinished |
| Human accepted / 2026-09-08 | Invited access, synthetic data; uploads/email/payments disabled initially | Any enabled integration needs separate approval, safe credentials and required egress |
| Open | Spending limit and ongoing cost-check cadence | Initial human Console verification is recorded in [docs/server.md](docs/server.md); no spending limit or recurring cadence has been supplied |
| Open | Persistent data worth keeping, backups, monitoring, updates | Resolve backups before introducing valuable persistent data |
| Open | Rebuild scope for OCI resources themselves | Full rebuildability is the goal; starting from a new VM does not yet specify cloud provisioning |

The canonical hostname is `sokoladas.eu`; `www.sokoladas.eu` permanently redirects to `https://sokoladas.eu`, and HTTP redirects to HTTPS except the ACME HTTP-01 path. DNS/addressing and HTTPS are verified; Section 6 is closed.

## Recorded state and documentation

[docs/server.md](docs/server.md) consolidates the recorded instance/network inventory and historical setup evidence. The original baseline reported a running VM, working SSH/public access, ARM64 and Ubuntu confirmation. The September 6 change log reports creation of `marijus` and retention of `ubuntu` as fallback. These reports have not been reverified during documentation remediation.

The network/firewall baseline (TODO Section 3) is closed **Human accepted** on the recorded agent and human evidence, including final human OCI attachment/statefulness confirmation recorded 2026-09-08. Evidence and verification limits are in [docs/server.md](docs/server.md#section-3-closed-on-human-oci-evidence--recorded-2026-09-08--human-accepted); future application/database exposure checks remain in TODO Section 7. Marijus accepted the Section 3 baseline and documentation on 2026-09-08. The September 8 [Docker installation](docs/server.md#docker-host-installed-and-verified--2026-09-08--human-accepted) is **Human accepted**: Engine 29.8.0, Compose 5.5.1 and Buildx 0.37.0 on ARM64, sudo administration and bounded local logs. Docker’s normal startup added runtime bridge/NAT/forwarding rules; existing host rules and saved firewall/SSH files were preserved, with no new public listeners. LXD installer packages were retained. Section 4's deferred deployment port verification is now satisfied by the Section 6 evidence (Docker TCP 80/443 publication, DNAT/FORWARD, and reboot persistence), so Section 4 is closed; the remaining application/database port-privacy check belongs to Section 7.

| File | Responsibility |
|---|---|
| [AGENTS.md](AGENTS.md) | Workflow, authorization, and review rules |
| [README.md](README.md) | Purpose, intended architecture, approved/open decisions |
| [docs/server.md](docs/server.md) | Authoritative recorded inventory, observations, access/recovery notes, evidence |
| [docs/domain-https-plan.md](docs/domain-https-plan.md) | Section 6 proposed sequence, approval groups, verification and rollback |
| [docs/https-runbook.md](docs/https-runbook.md) | Section 6 certificate/HTTPS/renewal runbook and rollback (review only) |
| [docs/http-bootstrap-runbook.md](docs/http-bootstrap-runbook.md) | Section 6 group-4 HTTP bootstrap runbook (Human accepted) |
| [docs/application-architecture.md](docs/application-architecture.md) | Accepted Section 5 architecture, alternatives and implementation prerequisites |
| [TODO.md](TODO.md) | Unfinished work and prerequisites; no execution authorization |
| [CHANGELOG.md](CHANGELOG.md) | Historical work, verification, limitations, and review status for new entries |
| [.gitignore](.gitignore) | Narrow local exclusions for secrets and generated artifacts |

Use the responsibility-based authority rules in AGENTS when documents disagree. Prefer improving these existing files over adding empty policy or procedure documents.

## Reproducibility and proportionality

The long-term recovery sequence is a new OCI VM → minimal documented bootstrap → repository scripts/configuration → Docker services → restore needed data → DNS/TLS verification. It is a goal, not an existing tested procedure. Configuration that exists only in shell history is not yet reproducible.

Progress from manual understanding to documented commands, repeatable scripts, and Compose as useful work emerges. Verify `linux/arm64` support for images, native application dependencies, binaries, and tools before adoption.

Add a process, document, or automation only when it reduces a realistic risk, removes ambiguity, improves reproducibility, or saves meaningful work. Defer Terraform, Ansible, Kubernetes, elaborate CI governance, formal RTO/RPO processes, policy libraries, complex secrets systems, ownership matrices, ADR hierarchies, and large monitoring stacks until there is a concrete need. Short operational notes can stay in the server document until their size or use justifies separation.
