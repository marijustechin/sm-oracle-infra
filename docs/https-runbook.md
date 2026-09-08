# Section 6 groups 5–7 — certificate issuance, HTTPS and renewal runbook

**2026-09-08 — Human accepted. Section 6 is closed: steps 0–7 (including the §8 isolated replacement/reload test) and a controlled reboot-persistence test are executed, verified and Human accepted. A real on-schedule Let's Encrypt renewal remains an operational follow-up and is not claimed as verified. No push.** This runbook supplies the exact Compose changes, Certbot staging/production state layout, Nginx HTTP/TLS configuration, certificate mounts, the accepted renewal loop and Nginx certificate-change watcher, the OCI TCP 443 action, verification and failure/rollback for the completed Section 6 work. The [HTTP bootstrap](http-bootstrap-runbook.md) is **Human accepted** and has been superseded by the activated HTTPS proxy. Frontend, API and PostgreSQL are excluded.

Execution is human-assisted: Marijus performs every sudo command interactively and the OCI Console TCP 443 change, returning evidence before the agent advances. The agent performs local/unprivileged repository validation only. Do not request or handle the marijus sudo password, modify sudoers, grant passwordless sudo, or use ubuntu for agent execution.

## Goal

- Obtain one Let's Encrypt certificate for `sokoladas.eu` and `www.sokoladas.eu` (both SANs), validated first against the Let's Encrypt **staging** environment using state separate from production certificate/account state.
- After staging validation, obtain the production certificate with the accepted containerized Certbot model (webroot HTTP-01).
- Add Nginx TLS on TCP 443; only Nginx publishes host TCP 443; add stateful OCI IPv4 TCP 443 ingress only when the HTTPS listener is ready for activation. No IPv6 exposure.
- Canonical behavior:
  - `http://sokoladas.eu/*` → permanent (308) redirect to `https://sokoladas.eu/*`, except `/.well-known/acme-challenge/`.
  - `http://www.sokoladas.eu/*` → permanent (308) redirect to `https://sokoladas.eu/*`, except the ACME path.
  - `https://www.sokoladas.eu/*` → permanent (308) redirect to `https://sokoladas.eu/*`.
  - `https://sokoladas.eu/*` → maintenance `503` until the application is deployed.
- Preserve ACME HTTP-01 availability on TCP 80 for future renewals.
- Implement the accepted renewal loop and Nginx certificate-change detection/reload. No Docker socket mount and no cross-container Docker control.

## Files and intended layers

- [https/compose.yaml](../https/compose.yaml): proxy (80+443, full TLS config, `run-proxy` entrypoint) plus certbot (`run-renewal` loop) on `edge`; stable `letsencrypt` and shared `acme_webroot` volumes; bounded tmpfs for Certbot work/log. No `app`/`db` networks yet.
- [https/compose.ca-test.yaml](../https/compose.ca-test.yaml): staging-CA override that replaces only Certbot's `/etc/letsencrypt` source with `sokoladas-staging_letsencrypt_staging`. Nginx never mounts this test volume.
- [https/images.env](../https/images.env): nonsecret pinned digests.
- [https/proxy/nginx.conf](../https/proxy/nginx.conf): ACME path for apex/www without redirect; HTTP 308 to apex for everything else; HTTPS apex 503, HTTPS www 308, unmatched-host 444; loopback readiness. No upstreams, no HSTS, HTTP/2 on by default.
- [https/proxy/run-proxy](../https/proxy/run-proxy): `nginx -t` preflight before starting Nginx (fails the container on invalid config/certificate state), then a single Nginx child with an inline one-shot hourly certificate-change checker; check failures are non-fatal and retried next interval, only unexpected Nginx termination exits the container.
- [https/proxy/check-certificate](../https/proxy/check-certificate): one-shot fingerprint compare → `nginx -t` → `nginx -s reload` → record, with a stable-pair guard.
- [https/certbot/run-renewal](../https/certbot/run-renewal): `certbot renew --non-interactive` on startup, then every 12 hours with jitter; failures logged and retried.

### Image pins and ARM64 gates

| Image | Pin | Status |
|---|---|---|
| Nginx | `nginx:1.30.4-alpine@sha256:aed159a7f218b47bbdc020b9c74dfcfb6825a67b00d3b2c14c34cd38025fe098` | Already human-verified linux/arm64 in the bootstrap |
| Certbot | `certbot/certbot:v5.8.0@sha256:f70ad0adbb7e117f0fe42a63c553f28ea451edabc0148757b6efcd9735acaa20` | Multi-arch tag incl. `linux/arm64` (registry metadata); **verify linux/arm64 at pull** before any issuance |

The Certbot image entrypoint is `certbot`, runs as root, workdir `/opt/certbot`; its writable state paths are `/etc/letsencrypt` (config/accounts/certs), `/var/lib/letsencrypt` (work) and `/var/log/letsencrypt` (logs). These facts were read from registry metadata during preparation; confirm them on the pinned manifest at execution. The Nginx alpine image must still provide `wget`, `grep`, `cat`, `awk` and `sha256sum` (busybox) for the readiness probe and certificate checker; verify before activation as in the bootstrap.

| Layer | TCP 80 after this group | TCP 443 after this group |
|---|---|---|
| OCI Security List | Retain the accepted stateful TCP 80 | Add stateful IPv4 TCP 443 only at activation |
| Host INPUT | Unchanged | Unchanged; not the bridge-publication control |
| Docker publish/DNAT | Proxy `0.0.0.0:80:80` | Proxy `0.0.0.0:443:443` only |
| Nginx listener | HTTP on 80 (redirect + ACME) | TLS on 443 (apex 503, www 308) |
| External result | ACME token 200; other paths 308 to apex | Apex HTTPS 503; www HTTPS 308 |

## Certificate mounts and permissions

- `letsencrypt` (`sokoladas-staging_letsencrypt`): Certbot reads/writes `/etc/letsencrypt`; Nginx mounts the whole tree read-only at `/etc/letsencrypt` so `live/` → `archive/` symlinks resolve. Nginx references `/etc/letsencrypt/live/sokoladas.eu/fullchain.pem` and `/etc/letsencrypt/live/sokoladas.eu/privkey.pem`.
- `acme_webroot` (`sokoladas-staging_acme_webroot`): Certbot writes challenge tokens to `/var/www/acme`; Nginx reads them at `/var/www/acme` (`root` for `/.well-known/acme-challenge/`).
- Certbot runs as root inside its container; generated files are root:root (directories 0755, private keys 0600, certificates 0644). Nginx master runs as root and reads the private key at startup/reload; workers run as the `nginx` user and never read the key. `run-proxy`/`check-certificate` run as root inside the proxy container and can hash the certificate pair.
- Do not chmod the private key world-readable, mount the test volume into Nginx, or commit any certificate/account state. Protect `letsencrypt` recovery copies like secrets. The staging volume is disposable test state.

## 0. Preconditions and preflight

Approval must cover: the files above, staging issuance against the test CA with isolated state, production issuance, the single OCI TCP 443 rule, proxy recreation to add 443, canonical redirect/503 activation, renewal-loop startup, and the rollback below. Retain a working SSH session and confirm an available independent Serial Console recovery path before mutation. The hostname SSH fingerprint is `SHA256:Qt7o7y7xOUccDssX6R5xGkOfQ0oKGaEYnQlsZ+0usLI`; use existing trust, never disable host-key checking. DNS is complete and must not change.

The HTTP bootstrap proxy (TCP 80, serving ACME + 503) stays running through the certificate-issuance steps so HTTP-01 challenges resolve. Do not stop it before production issuance succeeds.

Copy only the reviewed files to a unique staging directory, then install to a unique release path (root-owned, group/other write removed), preserving exec bits on the three scripts:

```sh
ssh -i ~/.ssh/id_ed25519_oracle marijus@sokoladas.eu 'test ! -e ~/section6-https-review && mkdir -m 700 ~/section6-https-review'
scp -i ~/.ssh/id_ed25519_oracle -r https marijus@sokoladas.eu:section6-https-review/
ssh -i ~/.ssh/id_ed25519_oracle marijus@sokoladas.eu
```

In a dedicated server Bash subshell, stop on every failure; re-source the variables after reconnecting. Use `ssh -n` in scripted workstation checks.

```bash
set -euo pipefail
sudo -v
hostname
uname -m
sudo systemctl is-enabled netfilter-persistent
sudo ss -lntup
sudo docker ps
sudo docker network ls
sudo docker volume ls
sudo test ! -e /opt/sokoladas-staging/releases/section6-https-v1
sudo install -d -o root -g root -m 755 /opt/sokoladas-staging/releases/section6-https-v1
sudo cp -R ~/section6-https-review/https /opt/sokoladas-staging/releases/section6-https-v1/
sudo chown -R root:root /opt/sokoladas-staging/releases/section6-https-v1
sudo chmod -R go-w /opt/sokoladas-staging/releases/section6-https-v1
sudo test -x /opt/sokoladas-staging/releases/section6-https-v1/https/proxy/run-proxy
sudo test -x /opt/sokoladas-staging/releases/section6-https-v1/https/proxy/check-certificate
sudo test -x /opt/sokoladas-staging/releases/section6-https-v1/https/certbot/run-renewal
sudo test ! -e /root/section6-https-v1-evidence
sudo install -d -m 700 /root/section6-https-v1-evidence
sudo bash -euo pipefail -c 'iptables-save > /root/section6-https-v1-evidence/runtime.v4; ip6tables-save > /root/section6-https-v1-evidence/runtime.v6'
sudo cp -p /etc/iptables/rules.v4 /root/section6-https-v1-evidence/saved.v4
sudo cp -p /etc/iptables/rules.v6 /root/section6-https-v1-evidence/saved.v6
sudo bash -euo pipefail <<'BASELINE'
evidence=/root/section6-https-v1-evidence
iptables -S InstanceServices > "$evidence/instance-services"
iptables -S OUTPUT > "$evidence/output"
iptables -S INPUT > "$evidence/input"
ss -lntup > "$evidence/listeners"
sshd -T > "$evidence/sshd-effective"
BASELINE
S6_RELEASE=/opt/sokoladas-staging/releases/section6-https-v1
s6compose() { sudo docker compose -p sokoladas-staging -f "$S6_RELEASE/https/compose.yaml" "$@"; }
s6compose_staging() { sudo docker compose -p sokoladas-staging -f "$S6_RELEASE/https/compose.yaml" -f "$S6_RELEASE/https/compose.ca-test.yaml" "$@"; }
```

Confirm: no preexisting `sokoladas HTTPS` OCI rule, no existing `sokoladas-staging_letsencrypt` or `sokoladas-staging_letsencrypt_staging` volume, and the bootstrap proxy still healthy. Record the current `letsencrypt`-volume absence before issuance. Preserve SSH/established/related/loopback/ICMP exactly; no host INPUT/FORWARD/DOCKER-USER/OUTPUT/InstanceServices mutation.

## 1. Validate images and Nginx configuration locally

```bash
s6compose config --quiet
s6compose_staging config --quiet
s6compose pull proxy certbot
s6compose run --rm --no-deps --entrypoint sh proxy -c 'command -v wget; command -v grep; command -v cat; command -v awk; command -v sha256sum; nginx -v; uname -m'
s6compose run --rm --no-deps --entrypoint sh certbot -c 'command -v certbot; certbot --version; uname -m; command -v bash'
```

Require aarch64 for both images. `nginx -v` and `certbot --version` must report the pinned images. The proxy config references certificate paths that do not exist until issuance, so a full `nginx -t` is performed after production issuance (step 4), not here.

## 2. Staging-CA issuance (separate state)

Issue against the staging CA using only the test override, so production `/etc/letsencrypt` is never touched. `$SECTION6_ACME_EMAIL` is the account contact supplied by the owner at execution (not a secret to be committed).

```bash
s6compose_staging run --rm --no-deps --entrypoint certbot certbot \
  certonly --non-interactive --agree-tos --email "$SECTION6_ACME_EMAIL" \
  --server https://acme-staging-v02.api.letsencrypt.org/directory \
  --webroot -w /var/www/acme \
  --cert-name sokoladas.eu -d sokoladas.eu -d www.sokoladas.eu
```

Verify the staging result in isolated state (no private material printed):

```bash
s6compose_staging run --rm --no-deps --entrypoint certbot certbot certificates
s6compose_staging run --rm --no-deps --entrypoint certbot certbot renew --dry-run --non-interactive
```

Require: both SANs present, staging issuer (`(STAGING) Let's Encrypt`), a plausible validity window, and a successful staging dry-run. Confirm the production `letsencrypt` volume is still empty/unaffected and that Nginx never mounted the test volume. A failed staging run stops production issuance; do not install a staging certificate as trusted service.

## 3. Production issuance

Omit the test override; identical `certonly` options against the production directory.

```bash
s6compose run --rm --no-deps --entrypoint certbot certbot \
  certonly --non-interactive --agree-tos --email "$SECTION6_ACME_EMAIL" \
  --server https://acme-v02.api.letsencrypt.org/directory \
  --webroot -w /var/www/acme \
  --cert-name sokoladas.eu -d sokoladas.eu -d www.sokoladas.eu
```

Verify certificate facts without printing private keys:

```bash
s6compose run --rm --no-deps --entrypoint certbot certbot certificates
s6compose run --rm --no-deps --entrypoint sh certbot -c 'ls -l /etc/letsencrypt/live/sokoladas.eu/'
```

Require: trusted issuer `Let's Encrypt`, both SANs (`sokoladas.eu`, `www.sokoladas.eu`), correct chain/expiry, `fullchain.pem`/`privkey.pem` present via the `live` symlinks, and root-only key mode (0600). The certificate is written to `sokoladas-staging_letsencrypt`; no Nginx reload or 443 exposure has occurred yet. Do not use repeated forced issuance as a debugging loop.

## 4. Validate the candidate HTTPS config (no published ports)

Validate the full HTTPS config against the real certificate state in a one-shot container with **no published ports** (`run` does not publish service ports):

```bash
s6compose run --rm --no-deps --entrypoint nginx proxy -t
```

This loads the production certificate through the `letsencrypt` mount and checks the 80/443/8080 listeners without exposing anything. A failure here must not lead to activation; keep the working HTTP bootstrap.

## 5. Activate HTTPS (proxy 443 first, then OCI 443)

Order matters: bring up the 443 listener locally first, then open OCI so the listener is ready before public ingress exists.

Recreate only the proxy with the HTTPS compose (adds the 443 binding; a brief HTTP interruption is expected):

```bash
s6compose up -d proxy
s6compose exec -T proxy nginx -t
s6compose exec -T proxy wget -q -O - http://127.0.0.1:8080/health/ready
s6compose ps
```

Confirm the proxy publishes `0.0.0.0:80:80` and `0.0.0.0:443:443`, is healthy, and no other container publishes any port. The certbot renewal loop is **not** started yet.

Then, in the OCI Console, add exactly one rule to the currently attached `Default Security List for demo-vnc` (the list already carrying the accepted TCP 80):

| Description | Source type/value | Protocol | Source ports | Destination ports | Stateless |
|---|---|---|---|---|---|
| sokoladas HTTPS TCP 443 | CIDR / `0.0.0.0/0` | TCP / 6 | All | 443 | No |

Save, re-read, and compare: only this TCP 443 addition alongside the existing TCP 80 and SSH; no IPv6, no UDP 443, no NSGs. Record the actual OCID/attachment; do not guess IDs or duplicate an existing permit.

## 6. External verification

From a separate Mac terminal (HTTPS/SSH checks; not a renewed DNS assessment). `$S6_IP=79.76.117.246`.

```sh
ssh -n -o ConnectTimeout=10 -i ~/.ssh/id_ed25519_oracle marijus@sokoladas.eu true
# HTTP redirects (both names) except the ACME path:
curl --max-time 10 -sS -D - -o /dev/null 'http://sokoladas.eu/test?x=1'
curl --max-time 10 -sS -D - -o /dev/null 'http://www.sokoladas.eu/test?x=1'
# ACME exception must NOT redirect (serves or 404s, not 308):
curl --max-time 10 -sS -D - -o /dev/null 'http://sokoladas.eu/.well-known/acme-challenge/absent-token'
# HTTPS apex maintenance 503:
curl --max-time 10 -sS -D - -o /dev/null 'https://sokoladas.eu/'
# HTTPS www permanent redirect to apex:
curl --max-time 10 -sS -D - -o /dev/null 'https://www.sokoladas.eu/test?x=1'
# Externally served certificate for both names:
openssl s_client -connect "$S6_IP:443" -servername sokoladas.eu -verify_hostname sokoladas.eu -verify_return_error </dev/null
openssl s_client -connect "$S6_IP:443" -servername www.sokoladas.eu -verify_hostname www.sokoladas.eu -verify_return_error </dev/null
# TCP 443 reachable; other private ports stay closed:
nc -vz -G 3 -w 3 "$S6_IP" 80
nc -vz -G 3 -w 3 "$S6_IP" 443
nc -vz -G 3 -w 3 "$S6_IP" 111
nc -vz -G 3 -w 3 "$S6_IP" 3000
nc -vz -G 3 -w 3 "$S6_IP" 3001
nc -vz -G 3 -w 3 "$S6_IP" 5432
```

Require: fresh trusted SSH; HTTP apex/www both `308` with `Location: https://sokoladas.eu/...`; the ACME path returns no 308 (404 for a missing token is correct); HTTPS apex `503` with `Retry-After: 3600`, `Cache-Control: no-store`, `X-Robots-Tag: noindex, nofollow`; HTTPS www `308` to apex preserving path/query; `openssl s_client` verifies chain and hostname for both SANs without `-k`; TCP 80/443 connect while 111/3000/3001/5432 refuse/time out. Use `curl --resolve` first to isolate the listener from DNS, then repeat without `--resolve` to exercise real DNS. Do not use `curl -k`. Any unexpected service or listener must be investigated.

On the server, retain outputs and compare to preflight:

```bash
sudo cmp /etc/iptables/rules.v4 /root/section6-https-v1-evidence/saved.v4
sudo cmp /etc/iptables/rules.v6 /root/section6-https-v1-evidence/saved.v6
sudo bash -euo pipefail <<'POLICY'
iptables -S INPUT | cmp - /root/section6-https-v1-evidence/input
sshd -T | cmp - /root/section6-https-v1-evidence/sshd-effective
POLICY
sudo iptables -S INPUT
sudo iptables -t nat -S DOCKER
sudo iptables -vnL FORWARD --line-numbers
sudo ss -lntup
sudo docker ps --format 'table {{.Names}}\t{{.Ports}}'
s6compose ps -q proxy | xargs sudo docker inspect --format '{{json .HostConfig.PortBindings}} {{json .State.Health}}'
sudo bash -euo pipefail -c 'iptables -S InstanceServices | cmp - /root/section6-https-v1-evidence/instance-services; iptables -S OUTPUT | cmp - /root/section6-https-v1-evidence/output'
```

Only proxy publishes 80 and 443; 8080 stays container-loopback; no new unrelated listener; host policy and SSH unchanged; Docker adds only the expected DNAT/forwarding for the 443 publication.

## 7. Renewal loop and certificate-change behavior

Start the production renewal loop **after** successful activation (no test loop; no overlap with the dry-run below):

```bash
s6compose up -d certbot
s6compose ps
s6compose logs --tail 20 certbot
```

The loop runs `certbot renew --non-interactive` on startup then every 12 hours with jitter. Verify the startup cycle completed without error.

Renewal dry-run (production manifest; coordinate so it does not overlap the running loop's attempt):

```bash
s6compose run --rm --no-deps --entrypoint certbot certbot renew --dry-run --non-interactive
```

Dry-run exit 0 validates renewal using the test CA without installing its certificate; it may also mean no certificate was due.

Test the certificate-change/reload mechanism independently on the running proxy without corrupting live keys — invoke check-once against the fingerprint `run-proxy` recorded at startup and observe the "unchanged" path:

```bash
s6compose exec -T proxy sh -c '/usr/local/bin/check-certificate; echo exit=$?'
```

Require exit 0 with an "unchanged" message (the current pair already matches the recorded fingerprint at `/run/nginx-cert.fp`). A real replacement/reload test uses a controlled valid certificate replacement in isolated state and is performed only under the same human-assisted gate; a dry-run alone does not prove production replacement/reload. Record what was actually verified; hourly detection is intentional, and an operator-driven replacement always includes an explicit validated reload.

## 8. Isolated certificate replacement/reload test — review only (not executed)

Proves the complete proxy watcher path (fingerprint change → stable-pair re-read → `nginx -t` → `nginx -s reload` → new fingerprint recorded) without a second Let's Encrypt certificate, without touching production certificate state, and without any public exposure. It runs the same reviewed `run-proxy`, `check-certificate` and `nginx.conf` against locally generated self-signed certificates in a separate Compose project ([compose.certtest.yaml](../https/compose.certtest.yaml)) that publishes no ports.

### What this test proves and what it cannot prove

Proves:

- a valid fullchain/privkey replacement is detected by content fingerprint;
- `nginx -t` runs **before** every reload attempt (an invalid pair fails `nginx -t` and is not loaded);
- on a valid, stable change `nginx -s reload` is actually invoked and the served certificate changes;
- the new fingerprint is recorded only after the validated reload, with the pair unchanged after reload;
- an invalid/mismatched pair is never accepted and never triggers a reload.

Cannot prove:

- a real Let's Encrypt renewal (ACME account, HTTP-01 public challenge, renewal config/cadence, CA-side behavior);
- reboot persistence (no reboot in this test);
- the race guard against a pair changing mid-reload (present in code, not deterministically exercised);
- full-chain (leaf + intermediate) parsing nuances beyond what `nginx -t` checks on a self-signed cert.

### Test state and material (host, root-owned)

```
/root/section6-certtest-state/
  letsencrypt/live/sokoladas.eu/{fullchain.pem,privkey.pem}   # live pair under test
  stage/a/{fullchain.pem,privkey.pem}                          # initial valid cert A
  stage/b/{fullchain.pem,privkey.pem}                          # replacement valid cert B
  webroot/                                                      # empty ACME root
```

Generate two distinct self-signed certificates locally (no CA request):

```bash
sudo mkdir -p /root/section6-certtest-state/letsencrypt/live/sokoladas.eu \
             /root/section6-certtest-state/stage/a /root/section6-certtest-state/stage/b \
             /root/section6-certtest-state/webroot
sudo openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=sokoladas.eu" \
  -keyout /root/section6-certtest-state/stage/a/privkey.pem -out /root/section6-certtest-state/stage/a/fullchain.pem
sudo openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=sokoladas.eu" \
  -keyout /root/section6-certtest-state/stage/b/privkey.pem -out /root/section6-certtest-state/stage/b/fullchain.pem
sudo cp /root/section6-certtest-state/stage/a/fullchain.pem /root/section6-certtest-state/letsencrypt/live/sokoladas.eu/fullchain.pem
sudo cp /root/section6-certtest-state/stage/a/privkey.pem   /root/section6-certtest-state/letsencrypt/live/sokoladas.eu/privkey.pem
```

Record reference fingerprints for later comparison: the pair fingerprint `cat fullchain privkey | sha256sum` for A and B, and the x509 fingerprint `openssl x509 -fingerprint -sha256 -noout` for A and B.

### Procedure

1. Start the isolated test proxy (no host ports):

```bash
sudo docker compose -p sokoladas-certtest -f "$S6_RELEASE/https/compose.certtest.yaml" up -d
sudo docker compose -p sokoladas-certtest -f "$S6_RELEASE/https/compose.certtest.yaml" ps
sudo docker inspect sokoladas-certtest-proxy-1 --format '{{json .HostConfig.PortBindings}}'
```

Confirm the test proxy publishes no `0.0.0.0:` mapping and that `run-proxy` passed its own `nginx -t` preflight (container `Up`, not restarting).

2. Confirm the initial fingerprint and served certificate are cert A:

```bash
TEST_IP=$(sudo docker inspect sokoladas-certtest-proxy-1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
sudo docker exec sokoladas-certtest-proxy-1 cat /run/nginx-cert.fp
echo | openssl s_client -connect "$TEST_IP:443" -servername sokoladas.eu 2>/dev/null | openssl x509 -fingerprint -sha256 -noout
```

3. Valid replacement (install B into the live path) and invoke check-once once:

```bash
sudo cp /root/section6-certtest-state/stage/b/fullchain.pem /root/section6-certtest-state/letsencrypt/live/sokoladas.eu/fullchain.pem
sudo cp /root/section6-certtest-state/stage/b/privkey.pem   /root/section6-certtest-state/letsencrypt/live/sokoladas.eu/privkey.pem
sudo docker exec sokoladas-certtest-proxy-1 /usr/local/bin/check-certificate
```

Expect `change detected; validating configuration` then `reloaded; recorded new fingerprint`, exit 0. Confirm the state file now equals B's pair fingerprint and the served certificate fingerprint is now B (reload actually occurred). If the stable-pair guard reports "files changed during reload", re-invoke after the files are quiescent.

4. Invalid/mismatched pair (B certificate + A key) and invoke check-once:

```bash
sudo cp /root/section6-certtest-state/stage/b/fullchain.pem /root/section6-certtest-state/letsencrypt/live/sokoladas.eu/fullchain.pem
sudo cp /root/section6-certtest-state/stage/a/privkey.pem   /root/section6-certtest-state/letsencrypt/live/sokoladas.eu/privkey.pem
sudo docker exec sokoladas-certtest-proxy-1 /usr/local/bin/check-certificate; echo exit=$?
```

Expect `nginx -t failed; keeping previous fingerprint` and a non-zero exit. Confirm the served certificate is still B and the state file still holds B's pair fingerprint — the mismatched pair was never accepted and no reload occurred.

### Cleanup and rollback

```bash
sudo docker compose -p sokoladas-certtest -f "$S6_RELEASE/https/compose.certtest.yaml" down
sudo rm -rf /root/section6-certtest-state
sudo docker ps -a --filter 'name=sokoladas-certtest'    # expect empty
sudo docker network ls | grep -E 'certtest' || true      # expect no certtest network
```

Confirm the production `sokoladas-staging-proxy-1` and `sokoladas-staging-certbot-1` remain healthy and that external HTTPS, redirects, the ACME path and SSH are unaffected. The production `letsencrypt` volume and the Certbot renewal loop are never mounted or modified by this test.

## Failure handling and rollback

| Failure | Action |
|---|---|
| Staging issuance fails | Stay HTTP bootstrap; check DNS/AAAA/CAA, clock, paths, permissions and effective OCI/Docker forwarding. No production issuance. |
| Production issuance fails | Retain bootstrap and all state; inspect error/rate limits and retry deliberately. Never install staging certificates as trusted service. |
| Candidate `nginx -t` fails | Do not activate; keep the working HTTP proxy. If activation/recreation fails, select the bootstrap release and previous bindings; retain certificate volumes. |
| Unexpected web exposure | Withdraw only the OCI 443 rule added by this group, then remove the proxy 443 publishing. Preserve TCP 22/80, InstanceServices and Docker-owned chains. |

Exact rollback for this group:

1. OCI Console: remove only `sokoladas HTTPS TCP 443` (0.0.0.0/0, TCP, source ports All, destination 443, Stateless No). Preserve the accepted TCP 80 and every preexisting entry, especially SSH. No 443 rule from a prior group is removed.
2. In the server shell, revert the proxy to the bootstrap release (port 80 only) and stop the renewal loop:

```bash
sudo docker compose -p sokoladas-staging -f /opt/sokoladas-staging/releases/section6-http-v1/bootstrap/compose.yaml up -d proxy
s6compose stop certbot
s6compose rm -f certbot
sudo cmp /etc/iptables/rules.v4 /root/section6-https-v1-evidence/saved.v4
sudo cmp /etc/iptables/rules.v6 /root/section6-https-v1-evidence/saved.v6
sudo ss -lntup
sudo docker ps
sudo bash -euo pipefail -c 'iptables -S InstanceServices | cmp - /root/section6-https-v1-evidence/instance-services; iptables -S OUTPUT | cmp - /root/section6-https-v1-evidence/output'
```

3. There is **no manual host firewall rollback**: no host rules were changed. Docker withdraws the removed container's publication rules. Inspect that no port-443 DNAT/publishing remains. Do not restore a full saved runtime snapshot, flush chains, or remove Oracle/Docker rules.
4. From the Mac, rerun trusted `ssh -n ... true`; TCP 443 must no longer connect, TCP 80 keeps the bootstrap 503/ACME behavior. Preserve address, DNS, `letsencrypt`/`acme_webroot` volumes, releases and evidence. No prune, `down -v`, image deletion or SSH-policy relaxation. Use independent Serial Console if SSH is unavailable.

## Preparation verification and limits

Local preparation checks passed: Compose parsing for both manifests (including the staging override replacing Certbot's `/etc/letsencrypt` with the test volume), Bash/sh syntax for the three scripts, exec-bit presence, and documentation links/whitespace. Certbot image architecture/entrypoint facts were read from public registry metadata; the Nginx pin was already human-verified. No image was pulled or run, no live/OCI/DNS/SSH action occurred, and no commit or push was made.

Remaining execution gates (unchanged): current recovery/Console availability, exact ACME contact/terms and account email, actual `linux/arm64` pull verification for the Certbot pin, and owner acceptance of the maintenance-only apex response. Reboot persistence, a real certificate replacement/reload test and a separate firewall-reload/reboot test remain explicitly unperformed. Application image contracts, PostgreSQL and frontend/API deployment belong to Section 7 and are not covered here. `sokoladas.online` stays untouched.
