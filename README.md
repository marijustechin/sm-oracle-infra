# sm-oracle-infra

Infrastructure and operational context for the `sokoladas.eu` demo/staging environment of the new `sokoladomeistrai` e-commerce application. This is separate from the current production shop.

Read [AGENTS.md](AGENTS.md) before work. The effective team is Marijus, the owner/developer/administrator, assisted by AI agents. The goal is an inexpensive, understandable, secure, ARM64-compatible environment that can be rebuilt without relying on shell history. OCI Free Tier is the cost objective. Dated human-observed allowance, volume eligibility, and cost evidence is recorded in [docs/server.md](docs/server.md); it does not guarantee future zero charges.

## Working method

Human decision → scoped task → implementation → verification and documentation → Ready for review → human review/corrections → Human accepted → explicitly requested commit.

[AGENTS.md](AGENTS.md) defines these states and authorization boundaries. Repository work does not authorize live changes. Documentation, proposed TODO removal, and change-log updates belong in the reviewable diff; they do not imply human acceptance.

## Intended architecture

The platform direction is a single OCI ARM64 VM with a minimal Ubuntu host, Docker Engine, and Docker Compose. Keep application runtimes and databases in containers. Host software should be limited to administration utilities, Git where needed, Docker, and justified security/backup/monitoring tooling.

The candidate application layout is:

```text
Internet HTTP/HTTPS → chosen DNS hostname → OCI public address
    → container reverse proxy (Caddy or Nginx)
        → Next.js frontend
        → NestJS API → PostgreSQL
```

Next.js/NestJS and the exact service layout remain provisional. PostgreSQL is the default database direction, containerized if used. Redis is only a possible internal service, not an approved dependency. Node.js/pnpm belong in application build/runtime containers. Public web traffic enters through the reverse proxy; SSH is a separate administrative service. Intended public ports are 22/tcp, 80/tcp, and 443/tcp; internal application/database ports must remain private. Key-based SSH is the intended access policy, not a claim that password authentication is disabled.

## Decisions and open questions

This is a lightweight decision record, not an authorization to execute tasks. Baseline directions below were already recorded before the 2026-09-07 documentation remediation and are retained by the approved remediation plan. Their original approval dates/evidence were not recorded; no historical approval is inferred.

| Status / date | Direction or question | Reason / boundary |
|---|---|---|
| Documented baseline / date unrecorded | Demo/staging on OCI ARM64; minimal host; Docker Engine and Compose | Low-cost, reproducible environment; application services in containers |
| Documented baseline / date unrecorded | Keep application source separate; no committed secrets or production customer data | Repository scope and data safety |
| Documented baseline / date unrecorded | Only SSH and web ports intended publicly; private internal service ports | Limit exposure; source restrictions remain open |
| Documented baseline / date unrecorded | Human architectural decisions and review; scoped agent implementation | Marijus remains the decision maker |
| Approved plan / 2026-09-07 | Separate repository/live authorization; explicit approval for destructive/access-breaking actions; lightweight review lifecycle | Remediation plan approved; implementation is Human accepted |
| Open | Root/www versus demo/API subdomains; dynamic versus reserved public address | Choose before changing DNS; `sokoladas.eu` is the documented available domain |
| Open | Caddy versus Nginx; final frontend/API/database layout | Candidate services are not a final application architecture |
| Owner decision / recorded 2026-09-07 | 2 GiB swapfile with swappiness 10; system locale `en_US.UTF-8`, timezone `Europe/Vilnius`; retain package-owned login locale behavior | Human changes/evidence and verification limits in [docs/server.md](docs/server.md); no additional host packages needed now, future installation is requirement-driven |
| Open | Docker storage/networks/volumes, restart/log policies | Resolve before dependent configuration |
| Open | Docker administration privileges; SSH restrictions; host firewall policy | Conventional rootful Docker-group access effectively grants host-root control |
| Open | Secret storage, delivery, access, rotation, and recovery | Resolve before deploying services needing secrets; no secrets platform selected |
| Open | Deployment/build strategy, CI responsibilities, deployment account, rollback | Application repositories and ARM64 build requirements still needed |
| Open | Audience/access, demo data, outbound email, payment sandbox behavior | Resolve applicable staging constraints before enabling those capabilities |
| Open | Spending limit and ongoing cost-check cadence | Initial human Console verification is recorded in [docs/server.md](docs/server.md); no spending limit or recurring cadence has been supplied |
| Open | Persistent data worth keeping, backups, monitoring, updates | Resolve backups before introducing valuable persistent data |
| Open | Rebuild scope for OCI resources themselves | Full rebuildability is the goal; starting from a new VM does not yet specify cloud provisioning |

Possible DNS layouts previously considered are `sokoladas.eu` with `www.sokoladas.eu`, or `demo.sokoladas.eu` with `api.demo.sokoladas.eu`. Neither is selected.

## Recorded state and documentation

[docs/server.md](docs/server.md) consolidates the recorded instance/network inventory and historical setup evidence. The original baseline reported a running VM, working SSH/public access, ARM64 and Ubuntu confirmation. The September 6 change log reports creation of `marijus` and retention of `ubuntu` as fallback. These reports have not been reverified during documentation remediation.

Detailed hardening and Docker installation are not established by repository evidence. Absence of scripts or configuration does not prove software is absent on the server.

| File | Responsibility |
|---|---|
| [AGENTS.md](AGENTS.md) | Workflow, authorization, and review rules |
| [README.md](README.md) | Purpose, intended architecture, approved/open decisions |
| [docs/server.md](docs/server.md) | Authoritative recorded inventory, observations, access/recovery notes, evidence |
| [TODO.md](TODO.md) | Unfinished work and prerequisites; no execution authorization |
| [CHANGELOG.md](CHANGELOG.md) | Historical work, verification, limitations, and review status for new entries |
| [.gitignore](.gitignore) | Narrow local exclusions for secrets and generated artifacts |

Use the responsibility-based authority rules in AGENTS when documents disagree. Prefer improving these existing files over adding empty policy or procedure documents.

## Reproducibility and proportionality

The long-term recovery sequence is a new OCI VM → minimal documented bootstrap → repository scripts/configuration → Docker services → restore needed data → DNS/TLS verification. It is a goal, not an existing tested procedure. Configuration that exists only in shell history is not yet reproducible.

Progress from manual understanding to documented commands, repeatable scripts, and Compose as useful work emerges. Verify `linux/arm64` support for images, native application dependencies, binaries, and tools before adoption.

Add a process, document, or automation only when it reduces a realistic risk, removes ambiguity, improves reproducibility, or saves meaningful work. Defer Terraform, Ansible, Kubernetes, elaborate CI governance, formal RTO/RPO processes, policy libraries, complex secrets systems, ownership matrices, ADR hierarchies, and large monitoring stacks until there is a concrete need. Short operational notes can stay in the server document until their size or use justifies separation.
