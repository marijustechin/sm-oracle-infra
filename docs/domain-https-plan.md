# Section 6 — Domain, stable addressing and HTTPS implementation plan

**2026-09-08 — Human accepted. Section 6 is closed: groups 1–7 are implemented, verified and Human accepted, including a controlled reboot-persistence test.** Groups 1–4 (stable addressing, DNS, HTTP bootstrap), group 5 (staging-CA issuance), group 6 (production issuance and HTTPS activation) and group 7 (renewal loop, isolated replacement/reload test, reboot persistence) are complete. The [group-4 runbook](http-bootstrap-runbook.md) and [HTTPS runbook](https-runbook.md) record the executed procedures. Two operational follow-ups remain (not implementation work): the first real on-schedule Let's Encrypt renewal before the certificate expires (2026-12-07), and reserved OCI public IPv4 pricing/status.

## Established inputs and scope

The human reports that sokoladas-demo now has reserved public IPv4 `79.76.117.246` on unchanged primary private IPv4 `10.0.0.52`; OCI now permits TCP 22 and 80, with no TCP 443 ingress in the supplied screenshot. Host INPUT remains unchanged, permitting new TCP 22; Docker-published HTTP uses DNAT/FORWARD instead. External HTTP is verified, and HTTPS remains unavailable. The [recorded inventory](server.md) supplies dated evidence: exactly one attached list, `Default Security List for demo-vnc`, stateful ingress, no NSGs in the inspected attachment set, unrestricted stateful IPv4 list egress, iptables-nft/netfilter-persistent, and Docker-managed forwarding/NAT. Historical lists and saved rules are not guaranteed live state.

[Section 5](application-architecture.md) is Human accepted: canonical `https://sokoladas.eu`, permanent www-to-apex and HTTP-to-HTTPS redirects except HTTP-01 challenges, containerized Nginx/Certbot, shared certificate/webroot volumes, a 12-hour renewal loop and hourly certificate-content checks. `sokoladas.online` remains reserved and untouched: no records, certificate names or redirects for it. No demo prefix, IPv6 enablement, UDP 443, app/API/database deployment or new management service is proposed.

Section 6 can establish HTTPS before application images exist. Start only `proxy` and `certbot` on ordinary `edge`, within the accepted `sokoladas-staging` project. Defer app/db network creation and upstream routes until actual application deployment; their accepted memberships remain unchanged. Return a static maintenance response on apex HTTPS, with no customer functionality, secrets or app health endpoints. The accepted invitation gate remains required before exposing the application; a generic maintenance response is proposed here for explicit approval.

## Stable-address completion evidence — 2026-09-08

Human-created resource `sokoladas-public-ip` now supplies `79.76.117.246`, replacing ephemeral `152.70.25.153`. OCI displays `79.76.117.246 (Reserved)` on `10.0.0.52`; the guest private IPv4 is unchanged. Existing-key SSH as marijus to the new address succeeded and identified the same ED25519 host key as the former address. No DNS/firewall/Nginx/Docker/application changes were made. The [inventory evidence](server.md#reserved-public-ipv4--human-executed-2026-09-08--ready-for-review) records verification limits.

OCI also displays `IP lifetime: Ephemeral` in the same row. Preserve this UI inconsistency without treating the reserved public resource as ephemeral; the field's scope/cause is unverified. This does not reopen completed address allocation/assignment. Pricing remains unverified from supplied evidence, not a reason to repeat the completed cutover. The proposed sequence below is retained for reproducibility, with completed groups marked; DNS completion is recorded below; group 4 has since completed; later certificate/TLS groups still require authorization.

## DNS completion evidence — 2026-09-08

Marijus changed Namecheap to `A @ 79.76.117.246` and `CNAME www sokoladas.eu`, removing `CNAME www parkingpage.namecheap.com` and `URL Redirect @ http://www.sokoladas.eu/`. Mac `dig +short` returned `79.76.117.246` for apex A; `sokoladas.eu.` then `79.76.117.246` for www A; only `sokoladas.eu.` for www AAAA; and no output for apex AAAA. No IPv6 address is published in these answers. Ignore the accidental AAA query entirely. See the [recorded raw human evidence](server.md#dns-prerequisite--human-verified-2026-09-08--ready-for-review).

**DNS prerequisite complete on human evidence:** both names resolve to the reserved IPv4 and are ready for the IPv4-only bootstrap. TTL and authoritative/CAA checks were not supplied; global propagation and HTTP reachability are not claimed. Routine just-before-use checks are not a reopening of the completed DNS change. No additional DNS changes are proposed now.

Additional human SSH verification: `ssh -i ~/.ssh/id_ed25519_oracle marijus@sokoladas.eu` connected successfully to `sokoladas.eu (79.76.117.246)`. The ED25519 fingerprint was `SHA256:Qt7o7y7xOUccDssX6R5xGkOfQ0oKGaEYnQlsZ+0usLI`, recognized by OpenSSH as the same key known for both `152.70.25.153` and `79.76.117.246`. This verifies hostname-based SSH reachability and continuity of server identity in addition to DNS resolution; it is not evidence of working HTTP/HTTPS. See [inventory evidence](server.md#hostname-ssh-identity--human-verified-2026-09-08--ready-for-review). Subsequent HTTP bootstrap evidence is linked above; TLS approval remains separate.

## Approval groups and ordered sequence

| Order / live group | Concrete approval required before execution | Exit gate / rollback point |
|---|---|---|
| 0. Fresh read-only preflight | Authorize scoped OCI/Namecheap inspection and SSH/read-only sudo, or supply equivalent human evidence | Exact resource IDs, DNS before-state, cost/quota and recovery evidence available; stop before any mutation if missing |
| 1. Reserve IPv4 — human completed | `sokoladas-public-ip` created by Marijus | Reserved address `79.76.117.246`; do not recreate |
| 2. Address cutover — human completed | Reserved address assigned to primary private IPv4 `10.0.0.52` | Existing-key marijus SSH and same ED25519 identity verified by human; outbound connectivity not newly evidenced |
| 3. DNS — human completed | Namecheap apex A/www CNAME installed; parking records removed | Mac resolution verifies reserved IPv4 and no IPv6 address; authoritative/global-cache verification not claimed |
| 4. HTTP bootstrap — human executed, verified | Approved proxy-only artifacts/webroot, OCI TCP 80, no host-policy mutation; no Certbot or 443 | External HTTP/SSH and Docker counters passed; token removed and both URLs 404; reboot and rollback not tested |
| 5. ACME test — human executed, verified | Approve staging-CA account/test issuance for both names using isolated test state | Staging issuance and renewal dry-run succeed; no test certificate presented as trusted production TLS |
| 6. Trusted HTTPS — executed and verified | Approve ACME account/contact/terms, production issuance, separately reviewed OCI TCP 443 ingress and Docker forwarding/publication (no automatic INPUT grant), proxy TCP 443 binding and maintenance-only HTTPS activation | Both names have trusted certificates, canonical redirects verified, apex returns intended 503 |
| 7. Unattended renewal and persistence verification — executed and verified | Approve starting accepted renewal/check loops, test invocations and any maintenance-window firewall reload/reboot separately | Renewal dry-run, controlled reload and fresh external/SSH checks pass; reboot persistence verified; on-schedule real renewal remains an operational follow-up |

These are approval boundaries, not requests to reapprove already accepted architecture. One later explicit authorization may cover several groups if it identifies the concrete resources, deltas and risks. Prepare executable repository artifacts and their local validation for review before asking to deploy them. Do not bundle unreviewed rollback destruction or a server reboot into routine verification.

## 0–2. Reserved IPv4 and recovery — reference procedure; allocation/cutover completed

Do not rerun these allocation/cutover steps. They describe the pre-change plan; only the completion evidence above establishes which checks were reported.

OCI assigns public IPv4 to a private-IP object on a VNIC. Create a reserved address in the instance's region, then remove the ephemeral association and assign the reserved object to the **same existing primary private-IP OCID**. No VM recreation or guest address/route edit is needed. The address changes: ephemeral objects cannot be converted to reserved objects. Reserved addresses persist independently and can be unassigned/reassigned within the region. See [OCI public-IP behavior](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/managingpublicIPs.htm).

Use the Console from the administrator's workstation, not a command sequence dependent on the SSH connection being changed:

1. Record instance, primary VNIC, primary private-IP and current public-IP OCIDs; region/compartment; current address/lifetime; route to enabled Internet gateway; all list/NSG attachments; and present service limits/IAM access. Confirm target is sokoladas-demo, not merely a matching display name.
2. Reconfirm independent OCI Serial Console access and ability to log in/administer. The owner tested this on September 7; that is historical evidence, not today's test. Retain a working marijus SSH session, test ubuntu fallback if specifically authorized, and record the SSH host-key fingerprint through a trusted existing session/console. Ubuntu SSH is not independent recovery for IP loss. Have working OCI Console authorization to reassign an address even if guest networking fails.
3. Create one unassigned reserved IPv4: Networking → IP management → Reserved public IPs, verified region/compartment, descriptive name `sokoladas-public-ip` (actual human-created resource name), Oracle address pool. Record its object ID/address/lifetime and confirm it is unassigned. Check actual tenancy quota; a generic documentation limit is not this account's allowance. [OCI creation procedure](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/reserved-public-ip-create.htm).
4. Before cutover, show the exact old/new address and private-IP mapping for approval. On the instance's primary VNIC/IP page, remove the ephemeral public IP, then select the existing reserved public IP for that private IP. Wait for assignment completion and re-read both objects. [OCI assignment procedure](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/reserved-public-ip-assign.htm).
5. Expect old-IP SSH sessions and established Internet flows to break, with a gap between removal and assignment. No fixed downtime is guaranteed. New outbound connections use the new public source address. Resume via the new address, verifying the saved host-key fingerprint; update the local SSH alias explicitly, never disable host-key checking or blindly delete known_hosts entries. Recheck hostname, architecture, private IP/routes, Docker and fresh SSH/sudo. Do not publish DNS until this succeeds.

**Pricing finding:** no current account-specific zero-cost claim is established. Oracle's older [VCN training material](https://www.oracle.com/a/ocom/docs/cloud/virtual-cloud-network-100.pdf) states public IPs, including unassociated reservations, had no charge. That historical statement is insufficient to guarantee today's tenancy terms. The current [VCN pricing page](https://www.oracle.com/cloud/networking/virtual-cloud-network/pricing/) and [VCN FAQ billing section](https://www.oracle.com/cloud/networking/virtual-cloud-network/faq/) do not by themselves establish this reservation's billing treatment. For any future allocation, obtain dated current pricing/Oracle confirmation covering assigned and unassigned Oracle-pool IPv4, verify account type/region/quota and have Marijus accept any charge. The completed human allocation does not establish billing terms. Confirm ongoing cost separately; do not repeat or reverse it merely because pricing evidence was not supplied. Unknown price remains a gate for any future allocation, not permission to assume Always Free. No load balancer, NAT gateway or paid IP product is needed by the proposed topology.

**Rollback:** before deleting ephemeral, cancel safely and keep the current attachment. After deletion, the old address is not a recoverable rollback target. Prefer fixing/reassigning the retained reserved object through OCI Console. If necessary and specifically approved, unassign (do not delete) reserved and allocate a new ephemeral to the same primary private IP; it will be another address and needs new DNS/SSH updates. Retain reserved state during troubleshooting. Do not recreate VM/VNIC, alter guest routes or release the reserved address as a shortcut.

## 3. Namecheap DNS — completed; original procedure retained for reference

Do not repeat this record change. The evidence above supersedes its pending status; the following is the original migration/verification guidance.

First inspect actual NS delegation and the full existing relevant records in the authorized DNS account. Namecheap registration does not prove Namecheap DNS hosting: Advanced DNS host records apply when its supported DNS service is authoritative. If nameservers point elsewhere, stop and use an approved plan for that provider; no nameserver migration is implicit. Inspect apex/www A/AAAA/CNAME/ALIAS/URL redirects, wildcard behavior, CAA and DNSSEC validity. Preserve MX/TXT/mail and unrelated records. Identify existing use of this apex before replacing it; the repository's separate-production-shop statement does not prove the domain is idle. [Namecheap A-record procedure](https://www.namecheap.com/support/knowledgebase/article.aspx/319/2237/how-can-i-set-up-an-a-address-record-for-my-domain/).

| Type | Namecheap Host | Value | Initial TTL |
|---|---|---|---|
| A | `@` | `79.76.117.246` (human-verified reserved assignment; recheck before DNS execution) | 300 seconds / 5 minutes if offered; otherwise shortest supported practical TTL, recorded before approval |
| CNAME | `www` | `sokoladas.eu` | Same initial TTL |

Do not use Namecheap URL Redirect records: Nginx implements HTTP status/Location and TLS. A CNAME supplies name resolution, not an HTTP redirect. Do not add AAAA; the accepted host has no global IPv6 exposure. Any conflicting existing AAAA/parking/redirect/A/CNAME needs an explicit identified replacement/removal in the DNS delta. Do not alter CAA without need: if restrictive CAA blocks Let's Encrypt, propose the exact change for approval; absence of CAA is not a reason to add an unrelated policy. [Namecheap record types](https://www.namecheap.com/support/knowledgebase/article.aspx/579/2237/which-record-type-option-should-i-choose-for-the-information-im-about-to-enter/).

Create/associate reserved IP and verify SSH **before** setting A. If replacing an active record, lower its TTL first under group 3 approval and wait out its previous TTL before replacement; lowering TTL does not evict cached answers. If no record existed, negative caching can also delay visibility. Keep low TTL through issuance/verification; propose 3600 seconds after a stable observation period, under the approved DNS group.

Run from an external workstation during authorized implementation; replace placeholders before use:

```sh
dig +short NS sokoladas.eu
dig @<AUTHORITATIVE_NS> sokoladas.eu A +noall +answer
dig @<AUTHORITATIVE_NS> www.sokoladas.eu CNAME +noall +answer
dig @1.1.1.1 sokoladas.eu A +noall +answer
dig @8.8.8.8 www.sokoladas.eu A +noall +answer
dig sokoladas.eu AAAA +noall +answer
dig www.sokoladas.eu AAAA +noall +answer
dig sokoladas.eu CAA +noall +answer
dig www.sokoladas.eu CAA +noall +answer
```

Query every authoritative NS, then independent recursive resolvers and the administrator's normal resolver. Require the intended chain/address, no conflicting IPv6 result and no SERVFAIL; sample checks cannot prove every cache worldwide has expired. Save old RRsets/TTLs securely before editing. DNS rollback restores those RRsets only if their old destinations are still controlled and functional. **Never restore an A record to the released ephemeral address**, which could be reassigned to someone else. Otherwise retain the reserved endpoint in maintenance mode or approve another controlled destination.

## 4. HTTP-only exposure and bootstrap — implemented and verified

The [exact group-4 runbook](http-bootstrap-runbook.md) is the reproducible procedure for the completed group; do not rerun deployment or create duplicate OCI rules. Earlier INPUT-only and pre-open-443 instructions are superseded: **add only OCI stateful IPv4 TCP 80 ingress; leave host INPUT and saved netfilter-persistent policy unchanged; publish only Nginx port 80**. No 443 permission, publication or listener in this group. Compose/Nginx behavior remains ACME direct without authentication/redirect and other HTTP 503.

The approved bootstrap exposure controls are the existing OCI allowlist plus deliberately reviewed Docker bindings and Docker-managed forwarding rules. External bridge traffic follows DNAT/FORWARD, not INPUT; an INPUT allow neither protects nor is required for that path. Custom DOCKER-USER rules are not proposed for this single-admin bootstrap; the runbook compares that option, records limitations and requires actual rule/counter validation after publication. Human external requests and before/after counters verify this path, with host-policy comparisons unchanged. Implementation is Ready for review, not yet Human accepted. Preserve InstanceServices, SSH, Docker-managed chains and netfilter-persistent; no broad FORWARD accepts or host-policy mutations.

Runtime and saved host-policy comparisons, Docker path verification, external token/503 checks and exact rollback are in the runbook. Rollback removes only the newly added OCI TCP 80 rule and proxy publication/container, with no manual host-rule restoration. A separate approved reboot test is required before claiming persistence verification. DNS/addressing remain complete.

## 5–6. Certificate issuance and HTTPS activation

The [HTTPS runbook](https-runbook.md) now supplies the root-owned release files, image pins, exact Certbot state layout and step-by-step commands; this section retains the design contract those artifacts implement. `SECTION6_COMPOSE` is the explicit absolute release manifest path (`/opt/sokoladas-staging/releases/section6-https-v1/https/compose.yaml`), and `SECTION6_CA_TEST_OVERRIDE` is the staging override (`.../compose.ca-test.yaml`). Every command runs as authorized human sudo administration; Certbot wrappers allow direct command override. These examples remain review material, not executed commands.

1. Create separate staging-CA state using a reviewed **test override manifest** that replaces only Certbot's `/etc/letsencrypt` source with a dedicated test named volume. Retain the real shared acme_webroot. Nginx must never mount this test certificate volume. Do not confuse ACME staging with the application's staging purpose.
2. With the test override selected, override the renewal-loop entrypoint and issue:

```sh
sudo docker compose -p sokoladas-staging -f "$SECTION6_COMPOSE" -f "$SECTION6_CA_TEST_OVERRIDE" run --rm --no-deps --entrypoint certbot certbot certonly --non-interactive --agree-tos --email "$SECTION6_ACME_EMAIL" --server https://acme-staging-v02.api.letsencrypt.org/directory --webroot -w /var/www/acme --cert-name sokoladas.eu -d sokoladas.eu -d www.sokoladas.eu
```

Check success, names, expiry and test issuer in the test state. Run the same test override with `renew --dry-run --non-interactive`. Confirm challenge access and that trusted volume/proxy mounts remain untouched. Failure stops production issuance. [Let's Encrypt staging environment](https://letsencrypt.org/docs/staging-environment/) supplies the test directory and explains its untrusted certificates.

3. After the production-issuance gate, omit the test override and use `https://acme-v02.api.letsencrypt.org/directory` with otherwise identical `certonly` options. This writes trusted state to `letsencrypt`. Confirm both SAN names, issuer, validity and matching key, without printing private material. Do not use repeated forced issuance as a debugging loop. [Certbot webroot and certificate management](https://eff-certbot.readthedocs.io/en/stable/using.html) supports the flow.
4. Mount the entire production `/etc/letsencrypt` tree read-only in Nginx, preserving live/archive symlinks. Explicit certificate paths are `/etc/letsencrypt/live/sokoladas.eu/fullchain.pem` and `/etc/letsencrypt/live/sokoladas.eu/privkey.pem`. Protect account/key state and recovery copies; do not commit them.
5. Before HTTPS activation, separately approve OCI TCP 443 ingress and verify its Docker forwarding path; do not assume bootstrap opened it. An INPUT permit is not required for the normal bridge-publication path. Validate a candidate HTTPS config against the real mounted certificate state in a separate one-shot Nginx validation container with **no published ports**, using a reviewed config override. On success, activate the full release configuration and recreate only proxy to add its previously absent 443 binding. Port publishing cannot be added by Nginx reload alone; expect a brief HTTP interruption. Validate `nginx -t` in the resulting proxy and verify readiness. Subsequent in-place certificate changes use graceful reload, not recreation.

Full HTTPS contract: apex TCP 443 terminates trusted TLS and returns plain generic `503 Service Unavailable` with `Retry-After: 3600`, `Cache-Control: no-store` and `X-Robots-Tag: noindex, nofollow` (headers on error responses too). No app/API upstream, auth form or environment detail. HTTPS www permanently returns 308 to fixed apex with path/query. At HTTPS activation, switch both HTTP names from bootstrap 503 to the accepted permanent HTTPS-apex redirect except the challenge location. Keep TLS 1.2/1.3, HTTP/1.1 and HTTP/2; no HSTS preload/includeSubDomains or UDP 443. Preserve the Section 5 app invitation policy for later application activation. Nginx's [configuration/reload behavior](https://nginx.org/en/docs/control.html) governs validation and graceful worker replacement.

External verification from outside the VM/VCN, after setting `SECTION6_IP` to the verified reserved address:

```sh
curl --resolve "sokoladas.eu:80:$SECTION6_IP" -sS -D - -o /dev/null 'http://sokoladas.eu/test?x=1'
curl --resolve "www.sokoladas.eu:443:$SECTION6_IP" -sS -D - -o /dev/null 'https://www.sokoladas.eu/test?x=1'
curl -sS -D - -o /dev/null https://sokoladas.eu/
curl -sS -D - -o /dev/null https://www.sokoladas.eu/
openssl s_client -connect "$SECTION6_IP:443" -servername sokoladas.eu -verify_hostname sokoladas.eu -verify_return_error </dev/null
openssl s_client -connect "$SECTION6_IP:443" -servername www.sokoladas.eu -verify_hostname www.sokoladas.eu -verify_return_error </dev/null
```

Do not use `curl -k`; use a trusted CA store. Require valid chain/hostname, both SANs, appropriate expiry, exact 308 Location and intended apex 503. A 503 is expected maintenance behavior here, not application readiness. Repeat without --resolve to verify actual DNS; --resolve alone bypasses it. After HTTPS activation, validate HTTP for www and the full configuration’s unknown-Host handling too. Test fresh SSH and external TCP 22/80/443 success; probe 111/3000/3001/5432 refusal/timeout with workstation `nc -vz -w 3` or an authorized scoped scan, and check UDP 443 remains outside OCI/publishing policy. Pair negative probes with rules/binding inspection; absence of listeners alone is not a firewall proof.

## 7. Renewal and persistence

The accepted loop and watcher are now concrete artifacts: [run-renewal](../https/certbot/run-renewal) and [run-proxy](../https/proxy/run-proxy) plus [check-certificate](../https/proxy/check-certificate). Start only the production Certbot service's accepted loop after issuance; no test loop. It runs `renew --non-interactive` on startup and every 12 hours with modest jitter, logs failures and retries next cycle. Nginx's fixed hourly check compares configured fullchain/key content; on change it validates then invokes `nginx -s reload`. The wrapper preflights `nginx -t` before starting Nginx (failing the container on an invalid configuration/certificate state) and runs Nginx as its only child with an inline one-shot hourly checker: certificate-check failures are logged and retried next interval, and only unexpected Nginx termination exits the container. Preserve before/after fingerprint consistency and no child-restart logic/general supervisor. No host timer or Docker control access is added.

Use `run --rm --no-deps --entrypoint certbot certbot renew --dry-run --non-interactive` with the production manifest, coordinated so it does not overlap the running renewal attempt. Dry-run validates renewal using the test CA without installing its certificate. Certbot exit 0 may also mean no certificate was due. Separately invoke the check-once operation to test changed/unchanged/invalid pairs in isolated test state; do not corrupt live keys to test failure. Demonstrate a controlled valid test certificate replacement and reload on a nonpublished test proxy before relying on hourly detection. Record what was actually verified; a dry-run alone does not prove production certificate replacement/reload. External trusted certificate checks remain the acceptance evidence after real replacement.

Log concise outcomes through accepted bounded Docker logs; Certbot work/log files remain size-bounded tmpfs. Marijus checks renewal failures and served expiry; assign an operating cadence before handover. Propose weekly expiry review, with failures investigated promptly and escalation at 14 days remaining. Routine renewal occurs early; hourly detection is intentional. Urgent operator rotation includes an explicit validated reload. Stable volumes survive container replacement; no `down -v`, prune or account/key deletion.

Verify recreated proxy and renewal containers retain state and names. Any firewall service reload or reboot needs a concrete maintenance/recovery approval: netfilter-persistent and Docker ordering may affect effective forwarding. Do not claim reboot persistence until fresh SSH, Docker binding/chain inspection, HTTP-01, trusted HTTPS and private-port checks pass afterward. If ordering fails, stop and prepare the specific correction; do not silently change Docker or firewall policies.

## Failure handling and genuine blockers

| Failure | Safe stopping/rollback action |
|---|---|
| Reservation quota/price unknown or create fails | Leave ephemeral attached; resolve evidence/approval before proceeding |
| New IP assignment/SSH fails | Use OCI Console to correct mapping and independent Serial Console for guest diagnosis; old ephemeral is not a fallback. Do not change SSH policy |
| DNS wrong/stale | Inspect authoritative first, then caches; restore only a known controlled destination. Keep reserved assignment while resolving |
| HTTP token or staging issuance fails | Stay HTTP bootstrap; check DNS/AAAA/CAA, clock, paths, permissions and effective OCI/Docker forwarding. No production issuance |
| Production issuance fails | Retain bootstrap and all existing state; inspect error/rate limits and retry deliberately. Never install staging certificates as trusted service |
| Candidate Nginx config fails | Do not activate it; keep working proxy. If activation/recreation fails, select saved bootstrap release and previous bindings. Retain trusted certificate volumes |
| Renewal/check failure | Keep serving last working certificate, log/diagnose before expiry, explicitly reload after correction. No volume reset or certificate churn |
| Unexpected web exposure | Withdraw only the OCI ingress added by the affected group (80 for bootstrap; 443 only if later approved/added), then remove its proxy publishing. Bootstrap has no host-policy mutation to restore. Preserve TCP 22, InstanceServices and Docker-owned chains |

Remaining live-execution gates are current resource/recovery evidence and routine DNS freshness checks (DNS prerequisite complete); exact signed-off deltas and rollback actions; authorized DNS account; verified native ARM64 images (the Certbot pin still needs a linux/arm64 pull check) and tested Compose/wrappers; ACME contact/terms; and approval of the maintenance-only response. These do not block producing the prepared artifacts. Application image contracts, database initialization, application secrets and deployment readiness belong to Section 7 and do not block proxy-only HTTPS. Do not touch sokoladas.online or reopen accepted Section 5 choices.

Documentation verification for this task: cross-checked accepted architecture, current human statements versus dated inventory, vendor procedures, ordered dependencies, approval gates, rollback limits, local links and whitespace. Human-reported new-IP SSH and OCI assignment are recorded above; DNS resolution is additionally human-verified as recorded above; no independent live tests or current-account pricing verification claimed. No implementation artifacts were executed, and no commit or push occurred. The HTTPS group artifacts ([compose](../https/compose.yaml), [Nginx config](../https/proxy/nginx.conf), [Certbot workflow](../https/certbot/run-renewal), [runbook](https-runbook.md)) are review candidates only.
