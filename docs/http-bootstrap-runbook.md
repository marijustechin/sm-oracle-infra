# Section 6 group 4 — HTTP bootstrap runbook

**2026-09-08 — Implemented and verified through human-assisted execution; Ready for review.** External HTTP, SSH, Docker packet-path and unchanged-policy checks passed; test-token cleanup was externally confirmed at 13:06:18 UTC. See [completion evidence](server.md#http-bootstrap-verified--2026-09-08--ready-for-review). This is the retained reproducible procedure, not an instruction to rerun completed actions. Section 6 remains open; Certbot, TLS, frontend, API and PostgreSQL remain excluded from this group.

Execution is now **human-assisted**. Marijus confirms independent Serial Console recovery remains available. The human runs every sudo command interactively and performs the OCI Console TCP 80 change, returning evidence before the agent advances. The agent may perform local/unprivileged repository validation only. Do not request or handle the marijus sudo password, modify sudoers, grant passwordless sudo, or use ubuntu for agent execution; ubuntu remains a human recovery/fallback path. The [earlier preflight record](server.md#http-bootstrap-execution-preflight--2026-09-08--incomplete) remains historical evidence. The completed deployment and verification are recorded in the inventory; no additional live action is authorized by this document.

## Files and intended layers

- [bootstrap/compose.yaml](../bootstrap/compose.yaml): one proxy on ordinary edge, stable ACME volume, explicit IPv4 port 80 binding, restart unless-stopped and loopback readiness. No certificate volume or Certbot service is created yet.
- [nginx.conf](../bootstrap/nginx/nginx.conf): ACME path for apex/www without authentication or redirects; every other ordinary HTTP request gets plain 503. The private readiness listener is the only exception. No upstream, TLS or certificate-check process runs.
- [prepare-web-firewall.py](../scripts/prepare-web-firewall.py): read-only byte comparison of saved policy against its preflight copy. Earlier add/remove operations are retired and rejected.
- [web-input-rules.sh](../scripts/web-input-rules.sh): read-only INPUT/FORWARD/DOCKER-USER/NAT evidence. No policy mutation; only `check` is accepted.

Nginx 1.30.4-alpine is pinned to ARM64 manifest `sha256:aed159a7f218b47bbdc020b9c74dfcfb6825a67b00d3b2c14c34cd38025fe098`, read from Docker Hub registry metadata during preparation. [Official image metadata](https://raw.githubusercontent.com/docker-library/official-images/master/library/nginx) lists ARM64 support. Human pull/inspection verified linux/arm64; Nginx syntax, wget/grep availability and runtime health checks passed. Repeat these gates for any future authorized rebuild. Image updates require an explicit pin change.

| Layer | TCP 80 after this group | TCP 443 after this group |
|---|---|---|
| OCI Security List | Add stateful IPv4 allow | No new permission; remains closed in recorded policy |
| Host INPUT | Unchanged; not the external bridge-publication control | Unchanged; no new permission |
| Docker publish/DNAT | Proxy only, `0.0.0.0:80:80` | None |
| Nginx listener | HTTP on 80 | None |
| External result to verify | ACME token 200; other paths 503 | No successful HTTPS connection expected |

### Approved bootstrap enforcement decision

Use **OCI ingress plus deliberately reviewed Docker publications** as exposure controls for this single-admin deployment. Do not add INPUT rules for Docker HTTP, and do not add custom DOCKER-USER policy now. Existing host-local filtering stays intact, including SSH and InstanceServices. Docker creates the necessary publication-specific forwarding/NAT rules; these are not broad manual FORWARD accepts.

Recorded evidence from the accepted Docker installation: iptables-nft backend, IPv4 forwarding enabled, FORWARD policy DROP, DOCKER-USER/DOCKER-FORWARD jumps before the original unconditional FORWARD REJECT. For a new external IPv4 connection the expected path is: OCI permits public TCP 80 → OCI maps public address to guest `10.0.0.52` → guest NAT PREROUTING/DOCKER DNATs port 80 to proxy's edge address → routing selects FORWARD → DOCKER-USER → Docker forwarding/bridge/publication rules → Nginx port 80. An accept there bypasses the later host FORWARD REJECT. Host INPUT is not on that routed path. iptables-nft is the compatibility backend, not a different INPUT-based enforcement model. This derivation follows [Docker's iptables documentation](https://docs.docker.com/engine/network/firewall-iptables/); human rule and counter evidence after startup supports this path; no packet capture is claimed.

DOCKER-USER would be warranted for an independent host-side source/port restriction or protection against accidental extra publications even when OCI allows them. It requires carefully scoped ingress matching, conntrack/original-destination handling after DNAT, established-return handling and persistence after Docker chain creation. A simplistic drop-all could break edge/ACME traffic. This bootstrap needs public HTTP-01 from arbitrary sources; OCI already restricts other public ports and only the reviewed proxy publishes 80. For one administrator, custom policy adds a second ruleset without a present additional restriction requirement. Revisit before widening OCI exposure or granting deployment privileges. This direction was explicitly approved for this bootstrap; implementation acceptance remains separate.

Limitations: OCI protection does not cover every local/VCN path; a future mistaken Docker binding can be reachable wherever network controls allow it. Docker administrators are root-equivalent. No claim of host defense against a malicious Docker administrator, destination filtering or universal container privacy is made. Preserve Docker-managed chains and Oracle InstanceServices; never add a broad FORWARD ACCEPT.

Before startup, inspect Docker daemon/network settings for nondefault direct routing or gateway modes. After startup, record proxy/edge IPs and the exact DNAT/forwarding matches, then compare rule counters before/after a fresh external request without resetting counters. External traffic should traverse DNAT/FORWARD rather than INPUT. Container-local health and host-loopback curl take different paths and cannot prove this. If observed settings/path differ, stop and review; do not open INPUT or remove REJECT as a workaround.

## 1. Approval, copy and preflight

Approval must cover the four files above, the single OCI TCP 80 rule, unchanged host policy, proxy startup, test-token creation/removal and rollback below. Retain working SSH and reconfirm an available independent Serial Console recovery path before mutation. The supplied hostname SSH fingerprint is `SHA256:Qt7o7y7xOUccDssX6R5xGkOfQ0oKGaEYnQlsZ+0usLI`; use existing trust, never disable checking. No new DNS/address action is requested.

After approval, from the repository on the Mac, copy only the reviewed files to a unique staging directory:

```sh
ssh -i ~/.ssh/id_ed25519_oracle marijus@sokoladas.eu 'test ! -e ~/section6-http-review && mkdir -m 700 ~/section6-http-review'
scp -i ~/.ssh/id_ed25519_oracle -r bootstrap scripts marijus@sokoladas.eu:section6-http-review/
ssh -i ~/.ssh/id_ed25519_oracle marijus@sokoladas.eu
```

In a dedicated server Bash subshell, stop on every failure. Session variables/functions below must be redefined after reconnecting; do not rely on an earlier SSH shell. Use `ssh -n` in scripted workstation checks so SSH cannot consume subsequent script input. Do not reuse an existing release/evidence directory or overwrite unknown work. Confirm the copied diff matches the reviewed files before installing:

```bash
set -euo pipefail
sudo -v
hostname
uname -m
sudo iptables --version
sudo systemctl is-enabled netfilter-persistent
sudo systemctl cat netfilter-persistent docker
sudo iptables -S
sudo iptables -t nat -S
sudo iptables -S DOCKER-USER
sudo ip6tables -S
sudo ss -lntup
sudo docker ps -a
sudo docker network ls
sudo cat /etc/docker/daemon.json
sudo systemctl cat docker
sudo test ! -e /opt/sokoladas-staging/releases/section6-http-v1
sudo install -d -o root -g root -m 755 /opt/sokoladas-staging/releases/section6-http-v1
sudo cp -R ~/section6-http-review/bootstrap ~/section6-http-review/scripts /opt/sokoladas-staging/releases/section6-http-v1/
sudo chown -R root:root /opt/sokoladas-staging/releases/section6-http-v1
sudo chmod -R go-w /opt/sokoladas-staging/releases/section6-http-v1
sudo test ! -e /root/section6-http-v1-evidence
sudo install -d -m 700 /root/section6-http-v1-evidence
sudo bash -euo pipefail -c 'iptables-save > /root/section6-http-v1-evidence/runtime.v4; ip6tables-save > /root/section6-http-v1-evidence/runtime.v6'
sudo cp -p /etc/iptables/rules.v4 /root/section6-http-v1-evidence/saved.v4
sudo cp -p /etc/iptables/rules.v6 /root/section6-http-v1-evidence/saved.v6
sudo bash -euo pipefail <<'BASELINE'
evidence=/root/section6-http-v1-evidence
iptables -S InstanceServices > "$evidence/instance-services"
iptables -S OUTPUT > "$evidence/output"
iptables -S INPUT > "$evidence/input"
ss -lntup > "$evidence/listeners"
sshd -T > "$evidence/sshd-effective"
BASELINE
S6_RELEASE=/opt/sokoladas-staging/releases/section6-http-v1
s6compose() { sudo docker compose -p sokoladas-staging -f "$S6_RELEASE/bootstrap/compose.yaml" "$@"; }
```

Review recovery, current INPUT order, InstanceServices, saved policy, boot ordering and unused ports before proceeding. Require no preexisting `sokoladas HTTP`/`sokoladas HTTPS` marker, unexpected web accept or conflicting project/service/volume needing adoption. If found, stop for reconciliation; rollback must not remove preexisting rules. Confirm no concurrent firewall changes. Preserve SSH/established/related/loopback/ICMP exactly. Do not install UFW, change backends, alter OUTPUT or relax SSH.

## 2. Preserve host policy and persistence

No runtime INPUT, FORWARD, DOCKER-USER, OUTPUT, InstanceServices or saved host-rule change is proposed. No TCP 443 permission at any layer in this group. The helpers are read-only; old `add`/`remove` commands intentionally fail.

```bash
sudo bash "$S6_RELEASE/scripts/web-input-rules.sh" check
sudo python3 "$S6_RELEASE/scripts/prepare-web-firewall.py" check /root/section6-http-v1-evidence/saved.v4 /etc/iptables/rules.v4
sudo cmp /etc/iptables/rules.v6 /root/section6-http-v1-evidence/saved.v6
```

Existing netfilter-persistent continues loading the unchanged host rules. Docker recreates its own bridge/NAT/publication rules when the restart-enabled proxy starts. Confirm boot ordering from the preflight units; no transient Docker chain may be saved through `netfilter-persistent save`. A service reload may disrupt Docker rules: do not execute one as verification. A separately approved reboot with independent recovery is required before claiming reboot-tested behavior; repeat host-policy comparison, chain/publication inspection, external HTTP and SSH afterward. If ordering is wrong, prepare a specific correction rather than flush/restore or add broad accepts.

## 3. Validate and start Nginx locally

```bash
s6compose config --quiet
s6compose pull proxy
s6compose run --rm --no-deps proxy -t
s6compose run --rm --no-deps --entrypoint sh proxy -c 'command -v wget; nginx -v; uname -m'
s6compose up -d --no-deps proxy
s6compose exec -T proxy nginx -t
s6compose exec -T proxy wget -q -O - http://127.0.0.1:8080/health/ready
s6compose ps
```

One-shot runs do not publish service ports. Require aarch64 and successful config/probe validation before startup. The custom main config intentionally bypasses stock entrypoint configuration edits and stock welcome files. Runtime stdout/stderr inherits accepted Docker local log rotation; verify via inspect below.

Create only the named nonsecret test token, using the same pinned image and a temporary writable volume mount; proxy keeps it readonly:

```bash
sudo docker run --rm --network none --entrypoint sh \
  --mount type=volume,src=sokoladas-staging_acme_webroot,dst=/var/www/acme \
  nginx:1.30.4-alpine@sha256:aed159a7f218b47bbdc020b9c74dfcfb6825a67b00d3b2c14c34cd38025fe098 \
  -ec 'mkdir -p /var/www/acme/.well-known/acme-challenge; test ! -e /var/www/acme/.well-known/acme-challenge/s6-http-v1-check; printf "%s\n" "sokoladas-section6-http-v1" > /var/www/acme/.well-known/acme-challenge/s6-http-v1-check; chmod 644 /var/www/acme/.well-known/acme-challenge/s6-http-v1-check'
s6compose exec -T proxy wget -q -O - --header='Host: sokoladas.eu' http://127.0.0.1/.well-known/acme-challenge/s6-http-v1-check
s6compose exec -T proxy wget -S -O - --header='Host: www.sokoladas.eu' http://127.0.0.1/ || test "$?" -eq 1
```

The last probe must show 503, not merely nonzero status; inspect it. Do not proceed if it fails for another reason. Local HTTP success does not establish public reachability.

## 4. OCI Console change — last exposure action

Use the currently attached Security List, reached through sokoladas-demo → primary VNIC → public-subnet → Security Lists → `Default Security List for demo-vnc`. Record its actual OCID and attachment/sharing before-state; do not guess an ID or create another list/NSG. Export or capture the full existing ingress/egress list. Add exactly one rule:

| Description | Source type/value | Protocol | Source ports | Destination ports | Stateless |
|---|---|---|---|---|---|
| sokoladas HTTP bootstrap TCP 80 | CIDR / `0.0.0.0/0` | TCP / 6 | All | 80 | No |

Save, re-read, and compare: only this TCP 80 addition, existing SSH and all other ingress/egress untouched. No TCP 443 or IPv6 additions, and no NSGs. TCP 443 belongs to the subsequent HTTPS activation review. Console operations are the exact human OCI procedure; no OCI CLI credentials/dependency or speculative OCID is introduced. If matching permits already exist, stop rather than duplicate or later delete rules not created by this group.

## 5. Verification and cleanup

From a separate Mac terminal (these are HTTP/SSH checks, not renewed DNS assessment):

```sh
ssh -n -o ConnectTimeout=10 -i ~/.ssh/id_ed25519_oracle marijus@sokoladas.eu true
curl --max-time 10 -sS -D - http://sokoladas.eu/.well-known/acme-challenge/s6-http-v1-check
curl --max-time 10 -sS -D - http://www.sokoladas.eu/.well-known/acme-challenge/s6-http-v1-check
curl --max-time 10 -sS -D - http://sokoladas.eu/
curl --max-time 10 -sS -D - 'http://www.sokoladas.eu/test?x=1'
curl --max-time 10 -sS -D - http://sokoladas.eu/.well-known/acme-challenge/absent-token
nc -vz -G 3 -w 3 79.76.117.246 80
nc -vz -G 3 -w 3 79.76.117.246 443
curl --max-time 5 -v https://sokoladas.eu/
```

Expected: same trusted SSH identity; token 200 with exact `sokoladas-section6-http-v1` body and no auth/Location; both ordinary paths 503 with maintenance body/Retry-After/no-store and no Location; missing token 404; TCP 80 connects. TCP 443 refusal/timeout and no HTTPS handshake are expected: verify independently that OCI has no added 443 permit, host policy is unchanged, and Docker/Nginx have no 443 publication/listener. Any successful TLS connection is unexpected and must be investigated. No `curl -k`. Optionally probe 111/3000/3001/5432 with the same nc syntax and require no connection; absence of listeners is not proof of firewall isolation.

On server, retain outputs and compare to preflight:

```bash
sudo bash "$S6_RELEASE/scripts/web-input-rules.sh" check
sudo cmp /etc/iptables/rules.v4 /root/section6-http-v1-evidence/saved.v4
sudo cmp /etc/iptables/rules.v6 /root/section6-http-v1-evidence/saved.v6
sudo bash -euo pipefail <<'POLICY'
iptables -S INPUT | cmp - /root/section6-http-v1-evidence/input
sshd -T | cmp - /root/section6-http-v1-evidence/sshd-effective
POLICY
sudo systemctl is-enabled netfilter-persistent
sudo iptables -S INPUT
sudo docker network inspect sokoladas-staging_edge
s6compose ps -q proxy | xargs sudo docker inspect --format '{{json .NetworkSettings.Networks}}'
sudo iptables -S FORWARD
sudo iptables -S DOCKER-USER
sudo iptables -t nat -S
sudo iptables -t nat -vnL DOCKER --line-numbers
sudo iptables -vnL FORWARD --line-numbers
sudo iptables -vnL DOCKER-USER --line-numbers
sudo iptables -vnL DOCKER --line-numbers
sudo iptables -vnL INPUT --line-numbers
sudo ss -lntup
sudo docker ps --format 'table {{.Names}}\t{{.Ports}}'
s6compose ps -q proxy | xargs sudo docker inspect --format '{{json .HostConfig.PortBindings}} {{json .HostConfig.LogConfig}} {{json .State.Health}}'
sudo bash -euo pipefail -c 'iptables -S InstanceServices | cmp - /root/section6-http-v1-evidence/instance-services; iptables -S OUTPUT | cmp - /root/section6-http-v1-evidence/output'
```

Require only proxy's 0.0.0.0:80 mapping and its HTTP process; 8080 stays container-loopback, 443 has no mapping/listener. Docker may expose via kernel DNAT without a docker-proxy process in ss; inspect bindings/NAT and external HTTP together. No new unrelated listener, no frontend/API/DB, accepted local log bounds, healthy proxy. Docker edge forwarding/NAT additions are expected automatic deltas; unchanged provider/SSH rules are required.

Remove only the test token, using the same helper image/mount:

```bash
sudo docker run --rm --network none --entrypoint sh \
  --mount type=volume,src=sokoladas-staging_acme_webroot,dst=/var/www/acme \
  nginx:1.30.4-alpine@sha256:aed159a7f218b47bbdc020b9c74dfcfb6825a67b00d3b2c14c34cd38025fe098 \
  -c 'rm -f /var/www/acme/.well-known/acme-challenge/s6-http-v1-check'
```

Repeat both external token requests: now 404. Stop here for human review. No certificate/account issuance, TLS publishing, redirect activation or renewal process. Reboot testing remains explicitly unperformed unless separately authorized; after any authorized reboot repeat SSH, saved/runtime rule, Docker, token/503 and private-port verification.

## 6. Exact rollback for this group

1. In the same attached OCI Security List, remove only `sokoladas HTTP bootstrap TCP 80` with source `0.0.0.0/0`, TCP, source ports All, destination 80, Stateless No. Verify it was added by this group and preserve every preexisting entry, especially SSH. No 443 rule was added, so none is removed. Re-read and compare to the saved list. Established tracked connections can persist briefly, so also stop proxy.
2. In the server shell, using the existing release/function definitions:

```bash
s6compose stop proxy
s6compose rm -f proxy
sudo python3 "$S6_RELEASE/scripts/prepare-web-firewall.py" check /root/section6-http-v1-evidence/saved.v4 /etc/iptables/rules.v4
sudo cmp /etc/iptables/rules.v6 /root/section6-http-v1-evidence/saved.v6
sudo bash "$S6_RELEASE/scripts/web-input-rules.sh" check
sudo ss -lntup
sudo docker ps
sudo bash -euo pipefail -c 'iptables -S InstanceServices | cmp - /root/section6-http-v1-evidence/instance-services; iptables -S OUTPUT | cmp - /root/section6-http-v1-evidence/output'
```

3. There is **no manual host firewall rollback**: no host rules were changed. Docker withdraws the removed container's publication rules; retained edge may retain its own bridge/NAT scaffolding. Inspect that no port-80 DNAT/publishing remains. Do not restore a full saved runtime snapshot, flush chains or remove Oracle/Docker rules. If policy comparison fails, investigate the unrelated delta instead of overwriting it.
4. From Mac rerun trusted `ssh -n -o ConnectTimeout=10 -i ~/.ssh/id_ed25519_oracle marijus@sokoladas.eu true`; neither web port should connect. Preserve address, DNS, ACME volume, release/evidence and edge network. No prune, `down -v`, image deletion or SSH-policy relaxation. Use independent Serial Console if SSH is unavailable.

## Preparation verification and limits

Local preparation checks covered Compose parsing, shell syntax, read-only helper comparison/refusal behavior, documentation links and whitespace. Human execution subsequently verified the pinned ARM64 image, Nginx syntax/health, port publication, external HTTP/SSH and before/after Docker counters. Saved IPv4/IPv6 and runtime INPUT/OUTPUT/InstanceServices/SSH policy comparisons passed. Test-token deletion was verified on-host and externally on both names. The earlier mutation-helper design was retired; the deployed helpers are read-only.

No reboot or rollback was executed. Screenshot resource-identity/egress visibility limits and source-specific external probe limits are recorded in the inventory. The working HTTP bootstrap is Ready for review, not Human accepted. Certificate issuance, TCP 443 and HTTPS activation require a later reviewed implementation and explicit authorization.
