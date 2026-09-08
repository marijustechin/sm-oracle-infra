# Infrastructure Change Log

## 2026-09-08

### Section 6 domain, DNS and HTTPS accepted and closed — Human accepted

Marijus explicitly accepted the complete Section 6 implementation on 2026-09-08, superseding the earlier Ready-for-review statuses: reserved public IPv4 and DNS, the HTTP bootstrap, staging-CA and production Let's Encrypt issuance, HTTPS activation with canonical apex/www redirects and maintenance 503, the containerized renewal loop and hourly certificate watcher, the isolated certificate replacement/reload test, and the reboot-persistence verification. Two operational follow-ups are explicitly preserved and are neither implementation blockers nor unfinished Section 6 work: (1) the first real on-schedule Let's Encrypt production renewal before the current certificate expires on 2026-12-07, and (2) the reserved OCI public IPv4 pricing/status follow-up (tracked in the README open decisions). No application deployment and no Section 7 work is authorized by this acceptance. No push.

### Section 6 reboot persistence verified — Section 6 closed (Ready for review)

Performed the approved controlled reboot of `sokoladas-demo` (human-assisted) and verified persistence end-to-end. Before-reboot baseline and after-reboot results match: the SSH host identity remained `SHA256:Qt7o7y7xOUccDssX6R5xGkOfQ0oKGaEYnQlsZ+0usLI`; the served certificate was unchanged (`CN=sokoladas.eu`, Let's Encrypt CN=YE2, 2026-09-08 → 2026-12-07, fingerprint `B9:5E:66:66…`); the saved firewall files `rules.v4`/`rules.v6` and `sshd -T` hashes were byte-identical; the Oracle `InstanceServices` chain was intact; Docker and containerd were enabled/active and the proxy (healthy) and certbot containers auto-returned with `0.0.0.0:80`/`443` restored, including the `nat DOCKER` DNAT rules to `172.18.0.2`. Externally after reboot: apex HTTPS 503, www 308, HTTP 308, ACME 404, TCP 443 reachable, TCP 111/3000/3001/5432 closed, fresh SSH succeeded.

Section 6 (Domain and HTTPS) is closed — implementation complete and verified, Ready for review. A real on-schedule Let's Encrypt renewal (next due before 2026-12-07) and ongoing reserved-IPv4 pricing remain operational follow-ups and are not claimed as verified here. No application deployment, no OCI/DNS/firewall change, no commit or push.

### Section 6 isolated certificate replacement/reload test executed and verified — Ready for review

Executed the reviewed isolated watcher test (human-assisted) using [compose.certtest.yaml](https/compose.certtest.yaml) and the same `run-proxy`/`check-certificate`/`nginx.conf`. The test project published no host ports (`PortBindings {}`) and started with self-signed cert A: the initial fingerprint `6411cc95…` matched A's pair, and the isolated endpoint served A (`E3:80:E3:B1…`). Replacing the full pair with cert B produced the expected path — fingerprint change detected → `nginx -t` success → `nginx -s reload` → new fingerprint `231eee95…` recorded → served cert changed to B (`E8:5A:FF:65…`). Installing the mismatched pair (B certificate + A key) produced change detection then `nginx -t` failure (`key values mismatch`, exit 1) with no reload, the recorded fingerprint remaining B and the served certificate remaining B.

Cleanup removed the container and network and deleted the state directory. Two transient shell issues occurred and were corrected: an SSH reconnect lost `$TEST_IP`, so one "served cert" check hit the production proxy (`B9:5E:66:66…`, the production certificate) instead of the test proxy; and a `down` with an empty release path failed once before being rerun correctly. After cleanup: production proxy healthy, Certbot renewal loop running, external apex HTTPS 503 / www 308 / HTTP 308 / ACME 404 correct, fresh SSH succeeds, no new public listener or Docker publication, and no leftover certtest container/network.

This proves the complete watcher path for a locally replaced pair (detection, `nginx -t` gating every reload, an actual reload, stable-pair recording, rejection of an invalid pair). It does not prove a real Let's Encrypt renewal (ACME/HTTP-01/cadence) or reboot persistence. No reboot, no production certificate-state change, no ACME request, no OCI/firewall/application change, no commit or push.

### Section 6 isolated certificate replacement/reload test designed — Ready for review (not executed)

Prepared, for review only, the smallest safe isolated test that proves the complete proxy watcher path without a second Let's Encrypt certificate, without touching production certificate state, and without public exposure. Added [compose.certtest.yaml](https/compose.certtest.yaml) (separate `sokoladas-certtest` project, no published ports, the same reviewed `run-proxy`/`check-certificate`/`nginx.conf` via read-only binds, isolated host state dirs) and documented the procedure in [docs/https-runbook.md](docs/https-runbook.md) §8: generate two self-signed certificates, verify the initial fingerprint and served certificate, perform a valid replacement and observe `nginx -t` → reload → new fingerprint, then a mismatched pair and observe `nginx -t` failure with no reload and unchanged fingerprint/state, followed by full teardown.

Documented what the test proves (fingerprint change detection, `nginx -t` gating every reload, an actual reload changing the served certificate, stable-pair recording, rejection of an invalid pair) and what it cannot prove (a real Let's Encrypt renewal, reboot persistence, the mid-reload race guard, full-chain parsing nuances). Verification: Compose parsing of the test manifest and documentation review. No execution, no reboot, no OCI/firewall/application change, no commit or push.

### Section 6 production renewal-loop startup and verification — Ready for review

Started the production Certbot renewal-loop service (human-assisted). The `certbot` container runs the reviewed `run-renewal` loop; its first cycle completed without error ("certbot renewal loop starting" → "certbot renewal cycle succeeded"; certificate not yet due, `expires on 2026-12-07 (skipped)`, no renewals attempted). A coordinated production-manifest `certbot renew --dry-run --non-interactive` reported "all simulated renewals succeeded". The proxy's `check-certificate` watcher reported "unchanged" (exit 0) against the currently served certificate, so no reload was attempted. The certbot container only exposes (does not publish) 80/443; only the proxy publishes `0.0.0.0:80`/`443`, and no host listener was added.

Post-check: apex HTTPS 503, HTTPS www 308 to apex, HTTP apex 308, ACME HTTP-01 path 404, TCP 443 reachable, fresh hostname SSH succeeds. No reboot, no OCI/firewall change, no application deployment, no commit or push. Ready for review, not Human accepted. Verified here: loop startup, first-cycle success, renewal dry-run, unchanged-path watcher. Not proven: an actual production certificate replacement and the reload path (not exercised without a reviewed isolated valid-certificate test), and reboot persistence.

### Section 6 HTTPS activation executed and verified — Ready for review

Activated HTTPS (human-assisted). The first activation attempt crashed because `run-proxy` used `#!/bin/bash`, which `nginx:alpine` lacks: `exec /usr/local/bin/run-proxy` returned "no such file or directory" (exit 255), putting the proxy in a restart loop. HTTP was restored via the reviewed rollback, then `run-proxy` was corrected to POSIX `sh` (and `set -euo pipefail` → `set -eu`); `run-renewal` was converted to POSIX `sh` for the same reason (jitter via `date +%s`). After the fix, the one-shot `nginx -t` validated the full HTTPS config against the production certificate, and the proxy was recreated publishing `0.0.0.0:80:80` and `0.0.0.0:443:443`, healthy, with only sshd (22) and docker-proxy (80/443) listening.

Marijus added the approved stateful OCI IPv4 TCP 443 rule (0.0.0.0/0), preserving existing rules. External verification passed: `https://sokoladas.eu/` returns 503 with the production certificate (CN=sokoladas.eu, Let's Encrypt CN=YE2, 2026-09-08 → 2026-12-07, SANs sokoladas.eu + www.sokoladas.eu); `https://www.sokoladas.eu/...` returns 308 to the same path/query on the apex; HTTP apex/www return 308 to the canonical HTTPS apex; the ACME HTTP-01 path returns 404 (not redirected); TCP 443 is reachable; TCP 111/3000/3001/5432 remain closed; fresh hostname SSH succeeds.

No renewal-loop startup, no application deployment, no further OCI/firewall changes, no commit or push. Ready for review, not Human accepted; the production renewal loop and reboot-persistence verification remain separate gates.

### Section 6 production certificate issuance executed and verified — Ready for review

Executed the approved production-issuance gate only (single attempt, human-assisted sudo). Issued one Let's Encrypt production certificate named `sokoladas.eu` using the accepted containerized Certbot webroot model against the production `sokoladas-staging_letsencrypt` volume and the existing HTTP bootstrap webroot: `certbot certonly --non-interactive --agree-tos --email <owner-supplied> --server https://acme-v02.api.letsencrypt.org/directory --webroot -w /var/www/acme --cert-name sokoladas.eu -d sokoladas.eu -d www.sokoladas.eu`.

Verification: `certbot certificates` shows `sokoladas.eu` with identifiers `sokoladas.eu www.sokoladas.eu` and expiry 2026-12-07 (`VALID: 89 days`, no staging marker); x509 inspection reports subject `CN=sokoladas.eu`, issuer `CN=YE2,O=Let's Encrypt,C=US`, validity 2026-09-08 → 2026-12-07, and SANs exactly `sokoladas.eu` and `www.sokoladas.eu`; the `live/sokoladas.eu` symlinks (`fullchain.pem`/`privkey.pem`/`cert.pem`/`chain.pem`) are present. `docker volume ls` now lists `sokoladas-staging_letsencrypt` alongside the separate `sokoladas-staging_letsencrypt_staging` and `acme_webroot`. The private key was not printed or captured.

The HTTP bootstrap remained healthy externally (apex/www 503, missing-token 404), fresh SSH succeeded, and TCP 443 still timed out. No proxy recreation, no TCP 443 publication, no OCI 443 ingress, no HTTP→HTTPS redirect activation, no renewal-loop startup, no commit or push. Ready for review, not Human accepted; HTTPS activation (candidate `nginx -t`, proxy 443, OCI 443, redirects) and the renewal loop remain separately authorized later groups.

### Section 6 staging-CA issuance gate executed and verified — Ready for review

Executed the approved staging-CA gate only, human-assisted (agent: local, registry and non-privileged SSH checks; Marijus: all sudo steps). Staged the reviewed `https/` artifacts to `~/section6-https-review` (local↔remote SHA-256 matched all 7 files), installed root-owned to `/opt/sokoladas-staging/releases/section6-https-v1`, captured baseline evidence under `/root/section6-https-v1-evidence` (saved/runtime IPv4/IPv6, INPUT/OUTPUT/InstanceServices, listeners, sshd -T), pulled both pinned images and confirmed `linux/arm64`, and validated both Compose manifests (production and staging override).

Issued a Let's Encrypt **staging** certificate with the isolated `sokoladas-staging_letsencrypt_staging` volume and the shared webroot: `certbot certonly --webroot -w /var/www/acme --cert-name sokoladas.eu -d sokoladas.eu -d www.sokoladas.eu` against the staging directory, using an owner-supplied contact email. Verification: `certbot certificates` reports both SANs (`sokoladas.eu`, `www.sokoladas.eu`), expiry 2026-12-07 and the `INVALID: TEST_CERT` staging marker; `renew --dry-run` reported all simulated renewals succeeded; `docker volume ls` lists only `sokoladas-staging_acme_webroot` and `sokoladas-staging_letsencrypt_staging`, so production `sokoladas-staging_letsencrypt` remains untouched; the running HTTP bootstrap stayed healthy externally (apex/www 503), fresh SSH succeeded, and TCP 443 still timed out.

No production issuance, no TCP 443 publication, no OCI 443 ingress, no proxy replacement and no renewal-loop startup occurred. No commit or push. This gate is Ready for review, not Human accepted; production issuance and HTTPS activation remain separately authorized later groups.

### Section 6 certificate, HTTPS and renewal implementation prepared — Ready for review

Prepared the remaining Section 6 group (certificate issuance, HTTPS activation, renewal) for review only. No live, OCI, DNS or SSH action, and no commit or push.

Added the `https/` release artifacts: a proxy+certbot [Compose manifest](https/compose.yaml) publishing only 80 and 443, a [staging-CA override](https/compose.ca-test.yaml) that replaces only Certbot's `/etc/letsencrypt` source with a disposable `sokoladas-staging_letsencrypt_staging` volume, nonsecret [image pins](https/images.env), the full [HTTP/TLS Nginx config](https/proxy/nginx.conf) (HTTP 308-to-apex except ACME, HTTPS apex 503, HTTPS www 308, unmatched-host 444), a [run-proxy](https/proxy/run-proxy) wrapper that preflights `nginx -t` before starting Nginx and runs Nginx as its only child with an inline one-shot hourly certificate-change checker (check failures logged and retried next interval; only Nginx termination exits the container), an independently testable [check-certificate](https/proxy/check-certificate) fingerprint/reload operation, and a [run-renewal](https/certbot/run-renewal) 12-hour Certbot loop with jitter. Pinned `certbot/certbot:v5.8.0` (multi-arch incl. linux/arm64) from public registry metadata; Nginx pin reused from the accepted bootstrap.

Applied two owner-directed implementation corrections before live approval: (1) an explicit `nginx -t` preflight in `run-proxy` so the container fails before starting Nginx on an invalid configuration/certificate state; (2) reconciled the run-proxy comments and documentation with the actual simple one-shot hourly checker lifecycle — certificate-check failures are non-fatal, logged and retried next interval, and only unexpected Nginx termination exits the container, with no separate checker daemon. The accepted Section 5 wording was corrected to match.

Wrote an exact [HTTPS runbook](docs/https-runbook.md) covering image/config validation, staging-CA issuance with isolated state, production issuance, candidate `nginx -t` validation with no published ports, ordered activation (proxy 443 before OCI 443), external/certificate/redirect/negative-port verification, renewal dry-run and certificate-change test, and a scoped rollback that withdraws only the OCI 443 rule and proxy 443 publishing. Updated the [Section 6 plan](docs/domain-https-plan.md), TODO and README to mark the group prepared-but-unexecuted.

Verification: Compose parsing for both manifests (including the staging override's volume replacement), Bash/sh syntax and exec bits for the three scripts, and documentation links/whitespace. Certbot image entrypoint/state-path facts were read from registry metadata; the Certbot pin still requires a linux/arm64 pull check and the config still requires a real `nginx -t` after issuance. No issuance, TLS, renewal, reboot or rollback test is claimed. This entry is Ready for review, not Human accepted.

### Section 6 HTTP bootstrap implemented and verified — Ready for review

Completed the approved human-assisted TCP-80-only bootstrap: human OCI ingress addition and pinned ARM64 Nginx deployment, with no host INPUT/persistent-policy changes. External apex/www token 200, maintenance 503 and missing-token 404 passed; fresh hostname SSH succeeded, TCP 80 connected, and TCP 443/111/3000/3001/5432 timed out from the Mac. Docker DNAT and publication ACCEPT counters increased from zero to 13 packets; FORWARD processed 126 packets through Docker chains with empty DOCKER-USER and unchanged terminal REJECT count. Final saved-policy, INPUT/OUTPUT/InstanceServices and SSH comparisons passed; proxy healthy, only port 80 published. Human removed the documented token; both URLs returned 404 at 13:06:18 UTC.

Reconciled inventory, README, plan and runbook; removed the completed bootstrap TODO while retaining TLS, renewal, future exposure and reboot verification. Fixed runbook SSH stdin handling for scripted checks. OCI screenshot attachment/egress visibility and source-specific probe limits remain explicit. No Certbot, TLS, application deployment, reboot or rollback test; Section 6 remains open. All privileged/live mutations were human-executed; no additional live action, commit or push. Local documentation/whitespace and helper syntax checks accompany this review; human acceptance remains pending.

### Section 6 local HTTP and OCI TCP 80 evidence — bootstrap verification pending

Recorded human apex/www token, maintenance 503 and missing-token 404 results. OCI screenshot shows four ingress rules including the approved stateful TCP 80 addition and existing SSH/ICMP, with no TCP 443. Description/OCID/attachment/egress visibility limits remain explicit. External forwarding verification and token cleanup are still required; no agent live action, commit or push.

### Section 6 human proxy startup and structural firewall gate — bootstrap incomplete

Recorded healthy Nginx bootstrap, only IPv4 port 80 publishing, edge 172.18.0.2, matching Docker DNAT/publication-specific forwarding rules and accepted bounded logs. Human comparisons establish unchanged saved host policy, INPUT/OUTPUT/InstanceServices and effective SSH policy. No structural mismatch with reviewed model; external traversal remains unverified until the later OCI/request/counter gate. No TCP 443, Certbot or application deployment. Token and OCI steps pending; no agent live execution, commit or push.

### Section 6 human image/config validation — bootstrap incomplete

Human evidence verifies the pinned Nginx linux/arm64 image, successful configuration test, Nginx 1.30.4/aarch64 and wget/grep availability. Compose created edge (bridge, IPv6 disabled, noninternal, no options) and the ACME volume; temporary validation containers were removed. No published proxy or OCI ingress change evidenced yet. Runtime forwarding and external checks remain pending; no agent live execution, commit or push.

### Section 6 human file staging — execution evidence; bootstrap incomplete

Recorded human creation of the root-owned section6-http-v1 release and root-only baseline evidence directory. Uploaded/release recursive comparisons and Compose parsing succeeded. Image/runtime validation, proxy startup, OCI TCP 80 and external verification remain pending. No firewall/SSH changes or agent live execution; no commit or push.

### Section 6 human privileged preflight — evidence recorded; execution incomplete

Reviewed human interactive-sudo output at 12:06:32 UTC: expected INPUT, empty DOCKER-USER, Docker jumps before FORWARD REJECT, no published DNAT, no containers/volumes or web listeners, accepted Docker logging and saved host policy. No material enforcement mismatch found. Preserved runtime-versus-saved Docker distinctions and pager-output limitation. Proceeding only to evidence/file staging; no deployment or OCI change verified. No agent live execution, commit or push in this evidence review.

### Section 6 authorized bootstrap preflight evidence — Ready for review; execution incomplete

Recorded successful strict-key SSH through sokoladas.eu at 12:00:17 UTC, sokoladas-demo/aarch64 identity, and marijus sudo requiring interactive authentication. Readable Docker logging configuration and service unit ordering were inspected. Execution awaits scoped sudo/recovery access and human coordination of the OCI Console step; no OCI connector/CLI/config is available here. No bootstrap files copied, images pulled, containers/tokens created, firewall/service changes, commit or push. TODO remains unfinished; this entry records preflight evidence, not completed implementation. Local Compose parsing, shell syntax and whitespace checks passed.

### Section 6 Docker enforcement and TCP-80-only correction — Ready for review

Revised bootstrap exposure to one stateful OCI TCP 80 addition and deliberate Docker port-80 publication. Removed unnecessary host INPUT mutations and all advance TCP 443 permissions. Existing host/netfilter-persistent policy stays unchanged; helpers now only read/compare and reject retired add/remove operations. Documented the recorded DNAT/FORWARD path, proposed OCI plus Docker controls versus custom DOCKER-USER policy, limitations and required actual rule/counter verification. No broad FORWARD permit, Oracle or Docker chain edits.

Updated runbook/plan, verification and rollback: only bootstrap OCI TCP 80 and proxy publication are withdrawn; no manual host policy restoration. TCP 443 is a later HTTPS approval. Compose/Nginx behavior preserved. Local syntax, parsing, read-only comparison/refusal and documentation checks passed; no live inspection, packet trace, changes, commit or push. Earlier entries retain superseded proposal history.

### Section 6 executable HTTP-bootstrap candidate — Ready for review

Prepared a proxy-only Compose manifest, explicit maintenance/ACME Nginx config, two narrow runtime/saved-rule firewall helpers and an exact human execution/verification/rollback runbook. Pinned the official Nginx ARM64 manifest using public registry metadata. OCI/host TCP 80/443 allowances, Docker port-80 publishing and actual HTTP listening are distinguished; no 443 publishing or HTTPS readiness is claimed. DNS and addressing evidence were not reassessed. Certbot and application services remain excluded.

Verification: local Compose parsing, shell syntax, saved-rule transformation/rollback tests and documentation checks. No live host/OCI changes or image/container execution; target Nginx config/runtime validation and recovery/firewall preflight remain explicit pre-exposure gates. No commit or push. Section 6 remains open; repository artifacts are review candidates, not evidence of deployment.

### Section 6 hostname SSH identity evidence — Ready for review

Recorded human successful existing-key SSH to sokoladas.eu (79.76.117.246), the exact ED25519 host fingerprint in docs/server.md, and OpenSSH recognition of that key for both the former ephemeral and current reserved addresses. This supplements DNS with verified SSH reachability/server identity; no HTTP/HTTPS or application readiness is inferred. Updated the Section 6 evidence without changing TODO completion or bootstrap approval scope. Documentation fingerprint transcription, local links and whitespace checked; no live access/changes, commit or push.

### Section 6 DNS evidence and next HTTP-bootstrap approval package — Ready for review

Recorded human Namecheap apex A/www CNAME changes and removal of parking CNAME/URL redirect. Mac A/AAAA evidence resolves both names to 79.76.117.246 with no IPv6 address; the accidental AAA query is excluded. Marked the DNS prerequisite complete and removed its completed TODOs without claiming worldwide propagation or independent testing.

Prepared only the next live approval package: exact stateful OCI TCP 80/443 additions, tagged host INPUT equivalents and netfilter-persistent storage, minimal Nginx edge/port-80 model, ACME token routing, server/external checks and scoped rollback. The latest human instruction explicitly replaces pre-HTTPS redirects with maintenance 503; accepted redirects return at HTTPS activation. TCP 443 is policy-only now; Certbot issuance, TLS publishing and renewal remain separate. No UFW, firewall-model replacement or application changes.

Verification: documentation consistency, local links/whitespace, human DNS-output interpretation and retained historical/accepted architecture evidence reviewed. Nginx snippet is proposed review text, not a deployed or runtime-tested file. No live access/changes, commit or push; Section 6 remains open.

### Section 6 reserved public IPv4 evidence — Ready for review

Recorded Marijus's completed stable-address change: reserved resource sokoladas-public-ip / 79.76.117.246 replaces ephemeral 152.70.25.153, assigned to unchanged primary private IPv4 10.0.0.52. Existing-key marijus SSH succeeded with the same ED25519 server identity. OCI displays the public address as Reserved while the same row says IP lifetime: Ephemeral; retained both observations without reclassifying the reserved address or inventing a cause.

Updated inventory, Section 6 plan, README and remaining TODO work; completed allocation/cutover is not reopened. Human reports no DNS, firewall, Nginx, Docker or application changes. Pricing and broader verification are not inferred. Checked documentation consistency, links, whitespace and preservation of historical evidence/accepted architecture. No independent live access or additional live changes, commit or push; Section 6 remains open.

### Section 6 domain, stable addressing and HTTPS plan — Ready for review

Added an ordered assessment/implementation plan for an OCI reserved IPv4 on the existing VM, apex A/www CNAME records, exact web ingress semantics, proxy-only bootstrap/maintenance HTTPS, isolated staging-CA tests, trusted issuance, accepted container renewal/hourly reload checks and rollback. Explicit approval groups preserve SSH/Serial Console recovery, InstanceServices and Docker-owned firewall rules. Released ephemeral IPv4 is not a rollback destination; current price/quota and DNS evidence remain live-execution gates. sokoladas.online is reserved and untouched; application deployment is deferred.

Verification: reviewed accepted Section 5 consistency, vendor documentation, sequencing, command placeholders, source/local links and whitespace. No live OCI/Namecheap/DNS/server assessment or mutations; no Compose/scripts or application artifacts created, no commit or push. Server inventory and accepted architecture are unchanged; Section 6 TODOs remain unfinished. Account-specific costs, recovery availability and runtime behavior are not newly verified.

### Section 5 application architecture accepted and closed — Human accepted

Marijus explicitly accepted the Section 5 architecture, including the final edge/app/db capability policy, canonical apex/www redirects, containerized Certbot renewal and hourly Nginx certificate checks. Recorded acceptance throughout the current design/README and removed completed Section 5 design TODOs. No unresolved architectural decision remains in Section 5; executable image contracts, PostgreSQL compatibility, registry selection, secret provisioning/custody, state-retention decisions and runtime verification remain explicit prerequisites in Sections 6–8. Closure does not authorize data loss or claim implementation readiness without these checks.

Verification: reviewed the complete documentation diff, local links, whitespace, absence of secret material, unchanged server inventory and retention of unfinished implementation work. No Compose, scripts or live changes. Human authorized committing the accepted documentation without pushing. Earlier entries below preserve the review history and superseded proposals; this acceptance applies to the final architecture only.

### Section 5 network, canonical hostname and containerized TLS revision — Ready for review

Recorded the human-directed edge/app/db policy: API has no initial outbound Internet capability; a separate egress network is deferred until an actual approved integration needs it. Recorded sokoladas.eu as canonical, permanent www-to-apex and HTTP-to-HTTPS redirects with the ACME challenge exception. Updated the in-principle approved containerized Nginx/Certbot model, replacing the earlier host timer with a renewal loop and proposing hourly certificate-content checks plus a narrowly scoped, independently testable validation/reload operation. Shared certificate/challenge storage remains unchanged. Other architecture contracts retain their status; Section 5 is not accepted or closed.

Verification: reviewed service/network memberships, TLS lifecycle, redirect/bootstrap consistency, remaining decisions, local links and whitespace. No Compose, scripts or live changes; docs/server.md unchanged. No runtime verification, commit or push. Earlier entries preserve the superseded proposals as history.

### Section 5 Nginx decision and revised TLS proposal — Ready for review

Recorded the human-approved Nginx choice: administrator familiarity, explicit conventional configuration and transparency are primary; resource efficiency is secondary. Revised the proposal with a short-lived Certbot webroot job, root-owned renewal timer/reload sequence, bootstrap and redirect behavior, explicit apex/www handling, shared certificate/challenge volumes, Nginx worker-readable access secret, DNS resolution and health checks. Nginx is accepted; this TLS workflow and remaining architecture are still proposals. Replaced the resolved proxy-selection TODO with unfinished TLS workflow work; Section 5 remains open.

Verification: reviewed documentation consistency, local links, whitespace and scope against the accepted inventory; consulted primary Certbot/Nginx documentation. No Compose or runtime configuration created, no live systems accessed, no commit or push; no runtime or exact Certbot ARM64-image verification claimed. Earlier proposal entry below records the initial proposal before this decision.

### Section 5 architecture proposal — Ready for review

Added a clearly proposed demo architecture and linked it from README/TODO: four long-running services in one Compose project, Caddy versus Nginx comparison, explicit application/database/egress networks, persistent DB/TLS state, conditional uploads, restricted per-service file secrets, health/migration/restart contracts and prebuilt ARM64 image delivery. The proposed server layout keeps secrets outside release/configuration files and application source outside this repository. Staging access, data, payment and email defaults and the genuine approval/application-contract blockers are explicit; no target decision is recorded as accepted.

Verification: compared the proposal with the accepted Section 4 baseline and public primary documentation, including current Nginx ACME support, PostgreSQL 18 volume layout, Next.js build/runtime environment behavior and Compose file-secret permission limits. Reviewed service/network/secret/volume consistency, links, whitespace and preservation of all existing TODO tasks and server inventory. No Compose/Dockerfile/Caddyfile implementation, application code, live server/OCI/DNS access, application-repository access, commit or push. No deployment/runtime verification is claimed. Section 5 remains open; this design is Ready for review, not Human accepted.

### Docker host installed and verified — Human accepted

Implemented the owner-approved rootful Docker target on sokoladas-demo. September 8 preflight at 10:01:35 UTC reconfirmed Resolute/ARM64, no conflicting packages, space and SSH access. Added the official scoped Docker key/deb822 source, authenticated APT metadata and reviewed the simulation. Installed exactly five packages at 10:02:39–10:02:56 UTC: docker-ce/docker-ce-cli 29.8.0, containerd.io 2.3.4, Buildx 0.37.0 and Compose 5.5.1, all arm64. No package removals/upgrades or optional runtime/management packages. Created daemon.json before auto-start: default Docker data-root, local logs, 10m × 3 files, compression. Retained default containerd storage and both LXD packages unchanged.

Verified through 10:04:34 UTC: Docker/containerd enabled and active, CLI/server ARM64, intended roots, effective local log options inherited by an official ARM64 hello-world container, empty docker group and denied marijus access without sudo, fresh SSH, unchanged public listener inventory and no failed units. Removed the test container/image; zero containers, images, volumes and build cache remain. Updated current README/inventory and removed completed Section 4 TODO items; actual deployment forwarding/published-port verification remains unfinished. Approved restart guidance is documented; no application deployed.

Docker's automatic startup enabled IPv4 forwarding, changed its FORWARD default to DROP and added bridge/NAT/forwarding chains. Host INPUT/InstanceServices and original FORWARD REJECT were preserved; saved IPv4/IPv6 rules and SSH hardening hashes match preflight. No manual firewall policy, OCI, DNS, SSH or Section 6 web-exposure changes. The default containerd config dump emitted a legacy-version migration warning but succeeded; no rewrite was needed and service journals had no warning-or-higher entries in the inspected interval. A local retained SSH shell lacked writable stdin; fresh post-install sessions verified access instead.

Verification includes package transaction/origins, daemon JSON validation, runtime/architecture/log configuration assertions, cleanup, LXD package verification, network comparisons, documentation diff, shell/JSON syntax and relative links/whitespace. No reboot/reload, bridge egress/published-port, rotation stress or rollback test is claimed. Historical observations remain preserved. No commit or push occurred during implementation.

Acceptance recorded 2026-09-08: Marijus explicitly accepted the Section 4 Docker host implementation and documentation, superseding the earlier assessment/proposal review status. Docker-managed runtime bridge/NAT changes and required future published-port verification remain unchanged. Final repository checks cover the accepted diff, local links, shell/JSON syntax, whitespace and preservation of remaining TODO work. No additional live changes; the owner authorized committing the accepted changes without pushing.

### Section 4 Docker assessment and implementation proposal — Ready for review

Performed authorized read-only SSH inspection of sokoladas-demo on September 8, 09:34:12–09:36:49 UTC. marijus sudo required authentication; the owner explicitly approved ubuntu read-only sudo, which succeeded. Recorded runtime/package/service/socket state, APT sources/keyring inventory, storage and standard data-root paths, users/rootless prerequisites, journald and Docker-relevant forwarding state. No Docker/containerd/runc/Podman installation found; LXD installer packages and its active activation socket are present, not a running LXD runtime. No evidence proves Docker data-root was never created historically.

Verified official Docker support for Resolute/arm64 against documentation and the public package index. Proposed exact package versions, sudo-based rootful administration without group grants, default Docker/containerd storage locations, bounded local logs, restart guidance, installation/ARM64 checks and withdrawal considerations. Compared rootless and docker-group alternatives; all target choices and live commands remain proposals. Updated README and replaced the completed initial inventory TODO with review/approval and fresh-preflight work; Section 4 remains open.

Verification: cross-checked live views, package dependencies and public compatibility evidence; reviewed documentation diff, proposed shell/JSON syntax, relative links and whitespace. No APT refresh, runtime invocation, software/service/configuration/network/group changes, secret collection, commit or push. Normal SSH/sudo audit effects remain. No installation, rootless execution, container networking, reboot persistence, rotation stress test or rollback result is claimed. Assessment and plan are Ready for review, not Human accepted.

### Section 3 closed on final human OCI evidence — Human accepted

Recorded Marijus's confirmation that public-subnet has exactly one attached Security List, Default Security List for demo-vnc, with Console pagination `1 - 1 of 1 total items`, and that the earlier ingress evidence showed Stateless: No for the recorded rules. This resolves the final attachment/statefulness task without independent OCI inspection.

Reviewed the existing host, OCI, rpcbind, external TCP, and UDP 123 evidence; no other unresolved requirement belongs to the present Section 3 baseline. Removed its completed TODO section without renumbering sections 4–10. Updated the inventory/current limitations and README completion status, and reconciled README's stale rpcbind proposal with the previously recorded human execution. Historical assessments and change-log entries are preserved; the latest inventory record supersedes their open-task statements.

Verification: compared documentation with the supplied evidence, reviewed the scoped diff, checked relative links and whitespace, and confirmed preservation of later TODO sections and historical entries. Remaining Docker/web enforcement belongs to sections 4/6. Existing gateway-flag, broader-reachability, and saved-rule/persistence limits remain explicit; no new live or universal exposure verification is claimed. No live access or changes, commit, or push occurred during the documentation reconciliation.

Acceptance recorded 2026-09-08: Marijus explicitly accepted the Section 3 network/firewall baseline and documentation, including the supporting September 7 Section 3 entries below. This supersedes their historical Ready for review statuses; technical conclusions, evidence limits, and completed TODO removal are unchanged. Final repository checks cover the full accepted diff, whitespace, local documentation links, secret/generated-file review, and preservation of the remaining roadmap. The owner authorized committing all accepted Section 3 changes; no push is authorized.

## 2026-09-07

### Human UDP 123 live-rule reconciliation recorded — Ready for review

Marijus reports consecutive read-only nft, iptables-save, and iptables -S checks on sokoladas-demo, all showing UDP 123 restricted to destination 169.254.169.254. Recorded semantic consistency of the address and /32 representations, removed the resolved TODO item, and updated README/current inventory wording. Earlier conflicting observations remain historical evidence; no cause is invented.

The supplied commands inspect live rules, so no fresh saved-file comparison or reboot-persistence result is claimed. This boundary does not retain the resolved live-rule discrepancy as a blocker. Section 3 remains open only for complete subnet Security List attachments and ingress statefulness evidence.

Verification: compared documentation with the human report, reviewed the scoped diff, checked relative links/whitespace and preservation of prior evidence. No independent live verification, live changes, commit, or push. Ready for review, not Human accepted.

### Human external TCP and OCI egress evidence recorded — Ready for review

Recorded Marijus's September 7 Mac tests against 152.70.25.153: TCP 22 connected; TCP 111, 80, and 443 timed out. These establish source-specific outcomes, not the filtering layer, UDP results, or universal reachability. Recorded one Default Security List for demo-vnc egress rule: 0.0.0.0/0, all protocols/ports, Stateless No (unrestricted stateful IPv4 permission at that list).

Reviewed UDP 123 against original evidence: single-address nft and /32 iptables destination syntax are equivalent. The genuine earlier conflict was nft's destination match versus no destination match in the human iptables-save output and agent-read saved file. Recorded both exact observations and retained only that unresolved evidence issue; both permit OCI NTP, so no policy change is justified.

Removed completed external TCP/egress tasks, narrowed Section 3 to complete subnet Security List attachments/ingress statefulness and UDP 123 reconciliation, and moved future container/web enforcement to sections 4/6. No further live configuration requirement was identified for the current baseline; Section 3 remains open for evidence reconciliation. Gateway flag and untested UDP/other sources remain limitations, not invented additional change requirements.

Verification: compared human evidence and original rule text, reviewed scoped documentation/TODO changes, checked links/whitespace, and preserved prior history. No live access or changes, independent OCI verification, commit, or push. Ready for review, not Human accepted.

### Human-executed rpcbind retirement recorded — Ready for review

Marijus reports successful execution of the approved `systemctl disable --now rpcbind.socket rpcbind.service` followed by `systemctl mask rpcbind.socket rpcbind.service`, both with sudo, on sokoladas-demo. Both units are masked and inactive (dead); the privileged port-111 socket check returned no output and `sudo rpcinfo -p` returned connection refused. Packages were retained. Exact execution/verification times were not supplied.

Recorded commands, human evidence, expected local portmapper failure, and verification limits in docs/server.md; removed the completed rpcbind TODO item. Earlier observations and rollback guidance remain preserved. Section 3 remains open for remaining OCI/network verification and later web/container enforcement; the UDP 123 discrepancy is unchanged.

Verification: compared documentation with the human report, reviewed the scoped edits, checked relative links/whitespace and preservation of remaining TODO items/history. No independent live verification, post-reboot result, broader service-health result, or fresh firewall comparison is claimed. No agent live access or changes, commit, or push. Documentation is Ready for review, not Human accepted.

### rpcbind dependency preflight — Ready for review

Read-only SSH inspection of sokoladas-demo on September 7 starting 17:40:18 UTC. Both rpcbind units remain enabled/running. Installed relationship scan found only nfs-common Depends on rpcbind and no installed recommendation. Cross-checked live and installed unit dependencies, mount/automount configuration, RPC registration, NFS configuration/statd state, and guest-tooling metadata. Found the dormant rpc-statd requirement on rpcbind.socket omitted from loaded-only reverse-dependency output; no active NFS data mount or other registered RPC service was found.

Conclusion: safe to disable/mask both units for the observed role while retaining packages, with separate human approval and execution still required. Recorded operational loss, exact unexecuted rollback/verification steps, and limits in docs/server.md; narrowed the existing TODO to disposition and authorized implementation. Section 3 remains open; no package-removal clearance or successful stopped-service test is claimed.

Verification: checked service state against sockets, package relations against APT, mount/unit/configuration and statd peer evidence, reviewed diff/relative links/whitespace. Noninteractive sudo required authentication; protected per-user jobs, other mount namespaces, and private/compiled agent internals were not exhaustively audited. The readable evidence supports the scoped service-only conclusion, not an absolute absence-of-consumers guarantee. No live service/package/configuration changes, OCI access, secret capture, commit, or push. Ready for review, not Human accepted.

### OCI network evidence and firewall direction recorded — Ready for review

Incorporated Marijus's September 7 Console observations: primary VNIC/subnet, ephemeral public IPv4, default Internet Gateway route, no NSGs or subnet IPv6 prefixes, and the three reported default Security List ingress rules. Combined these with prior guest and human privileged evidence without claiming independent OCI verification or new external reachability.

Recorded the owner's direction in README and the inventory: retain iptables-nft/netfilter-persistent, preserve InstanceServices, keep SSH available without fixed source restrictions, defer global IPv6 and web ingress, and keep RPC/internal service ports nonpublic. Proposed reversible rpcbind service/socket retirement after dependency preflight and separate approval, with package removal deferred. Recorded exact proposed commands, rollback, and verification scope; executed none.

Retained the UDP 123 discrepancy: both reported forms allow the OCI NTP endpoint, so it does not block retaining policy; reconcile before modifying/saving/restoring the affected rules. Narrowed Section 3 to unfinished evidence, rpcbind disposition/authorized implementation, external verification, and later web/container enforcement. Section 3 remains open. Complete Security List attachments, egress/statefulness, and broader reachability are not supplied.

Verification: compared documentation with the human report and prior guest evidence, consulted public primary technical documentation, reviewed the diff, and checked relative links/whitespace. Earlier history preserved. No new SSH inspection, independent OCI access, live changes, credentials, commit, or push. Ready for review, not Human accepted.

### Network and firewall assessment — Ready for review

Authorized read-only SSH inspection of sokoladas-demo on September 7, 17:11:55–17:13:07 UTC. Recorded guest interfaces, IPv4/IPv6 routes and enablement, complete returned TCP/UDP listener inventory, RPC package/service dependencies, firewall technology/persistence, and readable saved IPv4/IPv6 rules in docs/server.md. Updated Section 3 context and remaining verification/decision work; Section 3 remains open.

Observed wildcard SSH and rpcbind, loopback DNS/chrony sockets, and interface-bound DHCP. nfs-common depends on rpcbind, but no mounted NFS filesystem or other registered RPC program was identified. Image-supplied NFS support is a hypothesis, not established installation history. Saved OCI IPv4 rules reject input beyond SSH/ICMP/loopback/established traffic; saved IPv6 has ACCEPT policies only. No policy or rpcbind-retirement decision adopted.

Verification: cross-checked sockets with systemd units, network addresses/routes with networkctl and kernel values, package dependencies with local metadata, and persistence with readable rule files/plugins. Reviewed documentation diff, links, and whitespace. Agent sudo required interactive authentication; Marijus subsequently supplied privileged socket and loaded-rule output (save timestamps 17:14:33/49 UTC), confirming socket ownership, IPv4 input rejection, and empty IPv6 ACCEPT chains. Recorded a discrepancy: nft scopes UDP 123 to 169.254.169.254, while iptables-save and the saved file do not constrain the destination within the link-local chain. Exact agreement for that exception remains unverified. OCI configuration, public reachability beyond this SSH source/session, and other network namespaces remain unverified. Assessment documentation is Ready for review with these limits, not Human accepted or completed exposure verification. No live administrative changes, OCI/DNS changes, secret capture, commit, or push.

### OCI Serial Console recovery verified by owner — Ready for review

Marijus reports successful end-to-end recovery-access verification on 2026-09-07: created a local OCI console connection using a dedicated RSA key, reached the serial console, and logged in interactively as marijus using the local Linux password. This establishes access independent of normal SSH; no password SSH policy change is implied.

Recorded the human evidence and recovery sequence in docs/server.md, updated README's recovery status, and removed the final recovery-access item and now-complete TODO section 2 without renumbering later sections. Earlier assessment limitations and historical change-log entries remain preserved.

Verification: checked documentation against the supplied report, reviewed the diff, checked relative links/whitespace, and verified preservation of later TODO sections and prior history. No independent agent live verification or server/OCI changes, commit, or push. No credentials recorded. Exact connection commands/identifier and credential custody were not supplied; successful access does not establish repair of every boot/OS failure. Documentation is Ready for review, not Human accepted.

### Human-performed SSH hardening recorded — Human accepted

Recorded the owner's creation of `/etc/ssh/sshd_config.d/90-sokoladas-hardening.conf`: `PermitRootLogin no`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PubkeyAuthentication yes`, `X11Forwarding no`, and `AllowTcpForwarding yes`. Owner reports successful `sshd -t` (exit 0), confirmation of intended effective values with `sshd -T`, then SSH service reload. Exact execution times were not supplied.

Human verification: ubuntu key login and passwordless sudo worked before hardening. Root/opc key logins executed cloud-image redirects to ubuntu without shells; their authorized_keys entries were reported to contain forced commands and disabled port/agent/X11 forwarding. After reload, fresh marijus and ubuntu key sessions succeeded, ubuntu retained passwordless sudo, and direct root SSH was rejected.

Decisions: marijus primary administrator; ubuntu retained as tested recovery administrator; opc retained without cleanup. SSH remains on port 22; TCP forwarding intentionally remains enabled for administrative tunneling. Recorded exact configuration and evidence in docs/server.md and decisions in README.md.

Closed the supported TODO section 2 items. Retained its existing OCI console/recovery task: an alternate tested SSH administrator does not establish access when SSH/networking fails. The owner subsequently verified `sudo -l -U marijus` returned `(ALL : ALL) ALL`. Additional context-specific/negative authentication or forwarding tests were not supplied and are not claimed. Historical assessment results remain intact.

Verification: compared documentation with the human report, reviewed the task diff, checked relative links/whitespace and preservation of older history and later TODO sections. No additional live inspection, live changes, OCI/DNS access, commit, or push. This SSH hardening documentation update is Human accepted.

### SSH and access hardening assessment — Ready for review

Read-only SSH inspection on September 7, 14:12:21–14:13:08 UTC (remote clock). Verified marijus login using only publickey; server advertised only publickey for that session. Readable `60-cloudimg-settings.conf` sets `PasswordAuthentication no`; main file disables keyboard-interactive and enables PAM. Root/public-key default comments were not treated as effective configuration. SSH service/socket are active with wildcard IPv4/IPv6 port 22 listeners.

Recorded account/group and readable key metadata, local marijus password-set status, and cloud provisioning intent for ubuntu and opc. The opc cloud-image fragment sets `ssh_redirect_user: true`; actual protected key/redirect behavior remains unverified. Ubuntu fallback and cloud-intended passwordless sudo remain untested. No password-based SSH access was demonstrated or attempted.

Unprivileged `sshd -T` failed on unavailable host keys, `sudo -n -l` required interactive authentication, and unprivileged firewall queries/other-account key traversal were denied. No privilege bypass attempted. Exact read-only human checks and scope limits are recorded in docs/server.md. No effective-policy, firewall, or fallback success is claimed from failed checks.

Updated TODO section 2 context and changed the unconditional password-disable task into a decision after effective-policy verification, since current readable configuration already disables it. Section 2 remains open; no hardening implemented or new hardening decision adopted.

Verification: reviewed the task diff and evidence attribution, relative links, whitespace, and preservation of prior history/later roadmap sections. Only docs/server.md, TODO.md, and CHANGELOG.md updated. No live configuration, user/key/sudo/firewall/service/package changes, OCI/DNS access, commit, or push. Normal read-session audit/access-time effects were not suppressed. Human review is pending.

### Human-performed base server setup recorded — Human accepted

Recorded the owner's manual changes: generated `en_US.UTF-8` and `lt_LT.UTF-8`, set system `LANG=en_US.UTF-8` and timezone `Europe/Vilnius`, created/enabled a 2 GiB `/swapfile`, added `/swapfile none swap sw 0 0` to `/etc/fstab`, set `vm.swappiness=10` and persisted it in `/etc/sysctl.d/99-swappiness.conf`, then rebooted. Exact execution/reboot times were not supplied.

Human post-reboot verification: `timedatectl` reports the chosen timezone, synchronized clock and active NTP; `swapon --show` and `free -h` report 2 GiB swap; fstab contains the swapfile entry; `/etc/default/locale` and `localectl status` report `LANG=en_US.UTF-8`; `locale -a` includes both generated locales.

Decision: retain interactive-login `LANG=C.UTF-8` / `LC_CTYPE=C.UTF-8`. The owner traced this to Ubuntu `base-files`-owned `/etc/profile.d/01-locale-fix.sh` executing `locale-check C.UTF-8` and deliberately chose not to modify it. No additional host packages are required now; future installation remains requirement-driven. The earlier observed hostname `sokoladas-demo` needs no change for this task.

Removed completed TODO section 1 without renumbering later sections. Added the configuration/evidence record to docs/server.md and replaced README's open swap question with the owner's selected direction. Historical no-swap observations and earlier change-log entries remain intact.

Verification and limitations: checked documentation against the supplied report, reviewed the task diff, relative links and whitespace, and confirmed later TODO sections/history were preserved. No independent live inspection or changes were performed. Final human verification: post-reboot `sysctl vm.swappiness` returned `vm.swappiness = 10`. Exact swapfile creation commands/permissions and tested bootstrap automation were not supplied and are not claimed. The original section's swap-strategy decision is resolved; these evidence limits do not create an additional package-installation or locale-fix task. Base server setup and its documentation are Human accepted. No commit or push.

### Human-observed OCI cost verification recorded — Human accepted

Recorded Marijus's September 7 OCI Console observations in docs/server.md: `sokoladas-demo` uses `VM.Standard.A1.Flex` with 2 OCPUs and 12 GB RAM; the displayed Always Free A1 allowance is 3,000 OCPU-hours and 18,000 GB-hours/month (described as 4 OCPUs and 24 GB RAM). One 47 GB boot volume is marked Always Free, with no additional block volumes in the inspected compartment/region view. Cost Analysis for September 1–7 shows €0.00 Cost To Date and €0.00 each for Compute, Block Storage, and Virtual Cloud Network.

Removed the remaining TODO 0 cost-verification item and its now-empty section without renumbering later sections. Updated README's cost-evidence wording; an explicit spending limit and recurring check cadence remain open rather than being inferred from the zero-cost observation.

Verification: compared the documentation against the supplied human observations, reviewed the task diff, checked relative links and whitespace, and verified preservation of prior change-log entries and later TODO sections.

Limitations: human-reported, point-in-time control-plane evidence; no independent Console access, screenshots, or exports. The volume result is limited to the inspected compartment/region view; future zero cost is not guaranteed. Preserved historical/guest storage values separately without assuming an exact unit conversion. No live server access, OCI access or changes, commit, or push. This documentation update is Human accepted; earlier accepted work retains its status.

### Scoped live baseline inspection — Human accepted

Performed the authorized read-only SSH inventory/workload discovery for TODO section 0 against `marijus@152.70.25.153`, reporting hostname `sokoladas-demo`, on 2026-09-07 at 12:30:42–12:31:36 UTC (remote clock). Cost/Free Tier verification and TODO sections 1 onward were excluded.

Observed and documented in docs/server.md:

- Ubuntu 26.04.1 LTS, ARM64, Oracle kernel `7.0.0-1010-oracle`, two visible CPUs, about 11 GiB usable RAM, no active swap, one 46.6 GiB disk, and approximately 42 GiB free on root.
- Working SSH at the authorized public address, guest private address `10.0.0.52/26`, and default route via `10.0.0.1`; cloud configuration and address allocation type were not independently verified.
- OS/cloud-agent workloads, zero failed systemd units, and no recognizable application stack in the inspected views. TCP/UDP 111 wildcard listeners were observed alongside SSH; public reachability remains unknown.
- No common application/runtime packages, PATH executables, Docker socket, or common application data directories identified; OS/account state and package metadata backups exist. This is not proof of an empty/disposable server.

Repository changes: added dated live evidence and limitations while preserving historical reports; removed the completed inventory-recording item from TODO section 0 and narrowed the workload/data item to owner confirmation and unresolved paths. The cost item and all later sections remain unchanged.

Verification: cross-checked guest identity/resources, disk/mount views, running services/process names, sockets, installed package names, command availability, and selected directory metadata. Reviewed the repository diff, relative links, whitespace, preservation of prior history, and restriction to the three authorized documents.

Limitations: local sandbox initially blocked SSH, then the authorized retry succeeded. Protected-directory/size checks with `sudo -n` failed because interactive authentication was required; no password or configuration changes were attempted. At inspection time, valuable-data assessment required owner input; the subsequent confirmation below resolves the preservation requirement while protected paths remain uninspected. No OCI/DNS/cost inspection, external port scan, firewall/SSH policy audit, or backup/restore test occurred. No secret contents were collected. Read-oriented sessions may cause normal system audit/access-time effects; these were not suppressed or audited. No administrative mutations, commit, or push. Human review is complete and the scoped inspection is Human accepted.

Owner confirmation recorded 2026-09-07: this is a freshly provisioned demo VM with no pre-existing application or user data requiring preservation. Protected paths may contain normal OS/cloud-provider state but were not inspected; no valuable pre-existing application data is expected there. OS configuration and repository-documented infrastructure work may be treated as reproducible until persistent application data is introduced. This is owner confirmation, not additional inspection evidence or authorization for live/destructive changes.

Acceptance update: recorded the confirmation in docs/server.md and removed the resolved owner/data-confirmation item from TODO section 0. Cost verification remains open; later TODO sections and prior observations are unchanged. No additional server inspection or live changes, commit, or push.

### Documentation remediation — Human accepted

The human approved the remediation plan; this implementation is Human accepted.

Changed:

- Clarified repository versus live authorization, explicit approval for destructive/access-breaking actions, decision boundaries, intentional policy overrides, and read-only task behavior.
- Defined Implemented, Verified, Ready for review, and Human accepted; documentation and proposed roadmap/history updates are included before review.
- Assigned existing files distinct responsibilities; consolidated historical server inventory and evidence limitations in docs/server.md without external inspection.
- Reconciled account/status wording, removed existing baseline file-creation tasks from TODO, and ordered DNS/access tasks after their prerequisites.
- Added minimal secret/key/generated-file ignore patterns and handling rules; exposed Docker administration privileges and recovery prerequisites as decisions/checks.
- Kept operational secrets, staging boundaries, costs, backup needs, and actual access/network verification open; deferred unnecessary tooling and separate policy documents.

Verification:

- Reviewed the complete resulting six-file change, including previously untracked documents; checked whitespace, relative documentation links, and internal consistency.
- Checked ignore behavior using synthetic paths with Git: environment files, private-key patterns, and macOS metadata are excluded; sanitized `.env.example`, public keys, certificates, YAML configuration, and documentation remain eligible for tracking.
- No secrets or private material were introduced in the reviewed text. Ignore rules do not protect already tracked files and are not a secret scanner.

Limitations:

- Repository-only work: no server, OCI, DNS, or other external inspection or changes. No SSH/firewall/Docker/recovery improvements or fresh live verification are claimed.
- Historical observations retain their original uncertainty; the public address is not established as current. Operational follow-up remains in TODO.
- No commit or push; human review is complete and the remediation is Human accepted.

## 2026-09-06

### Base server preparation

Completed:

- Updated Ubuntu package indexes
- Upgraded installed packages
- Created `marijus` administrator account
- Added `marijus` to `sudo`
- Installed SSH public key
- Verified SSH login using key authentication
- Verified sudo access

Verification:

```bash
whoami
sudo whoami
```

Notes:

- Default ubuntu account retained as fallback administrator.
- Password SSH authentication has not yet been disabled.

Evidence qualification added 2026-09-07: the completion and key-login statements above are preserved historical reports. No captured command outputs were included. `whoami` and `sudo whoami` address user identity and sudo behavior, not SSH authentication method or effective password-authentication policy. Successful key login would not by itself establish key-only access. The password-authentication note describes the recorded September 6 state, not a fresh observation.
