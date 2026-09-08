# Sokoladas Demo Server

## Evidence and currency

This is the authoritative recorded inventory, not guaranteed live state. The historical OCI baseline below was consolidated from existing repository documentation on 2026-09-07 without external inspection. A subsequent authorized read-only SSH inspection on the same date established the separate live observations below. Original historical observation dates remain unknown unless stated. Live observations are point-in-time evidence, not configuration guarantees.

## Reboot persistence verified — Section 6 closed — 2026-09-08 — Human accepted

A controlled reboot of `sokoladas-demo` was performed and persistence verified. Before/after comparisons: SSH host identity unchanged (`SHA256:Qt7o7y7xOUccDssX6R5xGkOfQ0oKGaEYnQlsZ+0usLI`); served certificate unchanged (`CN=sokoladas.eu`, `Let's Encrypt CN=YE2`, 2026-09-08 → 2026-12-07, fingerprint `B9:5E:66:66…`); saved `rules.v4`/`rules.v6` hashes identical (`02bef650…`/`303649…`); `sshd -T` hash identical (`073d283d…`); Oracle `InstanceServices` chain intact; Docker and containerd enabled and active; proxy (healthy) and certbot containers auto-returned with `0.0.0.0:80`/`443` and `nat DOCKER` DNAT to `172.18.0.2` restored. Externally after reboot: apex HTTPS 503, www 308, HTTP 308, ACME HTTP-01 path 404, TCP 443 reachable, TCP 111/3000/3001/5432 closed, fresh SSH succeeded. Section 6 is closed and Human accepted. A real on-schedule Let's Encrypt renewal and reserved-IPv4 pricing remain operational follow-ups, not claimed as verified.

## Isolated certificate replacement/reload test verified — 2026-09-08 — Ready for review

The reviewed isolated watcher test was executed against a separate `sokoladas-certtest` project with no published host ports, using the production `run-proxy`/`check-certificate`/`nginx.conf` and locally generated self-signed certs A and B. Evidence: initial fingerprint `6411cc95…` equals A's pair and the served cert was A (`E3:80:E3:B1…`); a valid B replacement produced change detection, `nginx -t` success, reload and recorded fingerprint `231eee95…` with served cert B (`E8:5A:FF:65…`); a mismatched B certificate + A key produced `nginx -t` failure (`key values mismatch`, exit 1) with no reload, fingerprint remaining B and served cert remaining B. Cleanup removed the container, network and state directory. Production remained healthy: proxy healthy, renewal loop running, external HTTPS/redirects/ACME correct, fresh SSH, no new public listener. Proves the local replacement/reload path; a real Let's Encrypt renewal and reboot persistence remain unproven. Ready for review, not Human accepted.

## Production renewal loop started and verified — 2026-09-08 — Ready for review

Marijus started the production Certbot renewal-loop service. Evidence: `docker compose ps` shows certbot `Up` and proxy `Up (healthy)`; certbot logs show "certbot renewal loop starting" then "certbot renewal cycle succeeded" (certificate not due, expires 2026-12-07, no renewals attempted). A coordinated `certbot renew --dry-run --non-interactive` reported "all simulated renewals succeeded". The proxy watcher's check-once reported "check-certificate: unchanged" (exit 0) against the served pair. The certbot container exposes but does not publish 80/443; only the proxy publishes `0.0.0.0:80`/`443`.

External checks after the gate: apex HTTPS 503, HTTPS www 308, HTTP apex 308, ACME HTTP-01 path 404, TCP 443 reachable, fresh hostname SSH succeeds. Actual production certificate replacement/reload and reboot persistence remain unverified. Ready for review, not Human accepted.

## HTTPS activation verified — 2026-09-08 — Ready for review

Human-assisted activation. The first attempt failed because `run-proxy` used `#!/bin/bash`, which the `nginx:alpine` image lacks (`exec /usr/local/bin/run-proxy: no such file or directory`, exit 255), causing a restart loop; HTTP was restored via the reviewed rollback, and the wrapper was corrected to POSIX `sh` (with `run-renewal` converted for the same reason). After the fix, the one-shot `nginx -t` passed against the production certificate, and the proxy runs healthy publishing only `0.0.0.0:80:80` and `0.0.0.0:443:443`; host listeners are sshd (22) and docker-proxy (80/443) only.

Marijus added the approved stateful OCI TCP 443 ingress rule from `0.0.0.0/0`, preserving existing rules. External evidence: apex HTTPS returns 503 with the production certificate (subject `CN=sokoladas.eu`, issuer `Let's Encrypt CN=YE2`, 2026-09-08 → 2026-12-07, SANs `sokoladas.eu` and `www.sokoladas.eu`); HTTPS www returns 308 to the apex preserving path/query; HTTP apex/www return 308 to the canonical HTTPS apex; the ACME HTTP-01 path returns 404 (not redirected); TCP 443 is reachable while TCP 111/3000/3001/5432 remain closed; fresh hostname SSH succeeds.

No renewal loop started, no application deployment, and no further OCI/firewall change. Ready for review, not Human accepted.

## Production certificate issuance verified — 2026-09-08 — Ready for review

Marijus executed the approved production-issuance gate with sudo (single attempt). One Let's Encrypt production certificate named `sokoladas.eu` was issued via the containerized Certbot webroot model against the production `sokoladas-staging_letsencrypt` volume and the existing HTTP bootstrap webroot, using an owner-supplied contact email (recorded generically, not verbatim).

Evidence: `certbot certificates` reports `sokoladas.eu` with identifiers `sokoladas.eu www.sokoladas.eu` and expiry 2026-12-07 (`VALID: 89 days`, no staging marker). x509 inspection shows subject `CN=sokoladas.eu`, issuer `CN=YE2,O=Let's Encrypt,C=US`, validity 2026-09-08 → 2026-12-07, and SANs exactly `sokoladas.eu` and `www.sokoladas.eu`. The `live/sokoladas.eu` symlinks (`fullchain.pem`, `privkey.pem`, `cert.pem`, `chain.pem`) are present; the private key was not printed. `docker volume ls` lists `sokoladas-staging_letsencrypt`, `sokoladas-staging_letsencrypt_staging` and `sokoladas-staging_acme_webroot`.

The HTTP bootstrap remained healthy externally (apex/www 503), fresh SSH succeeded, and TCP 443 still timed out. No proxy recreation, TCP 443 publication, OCI 443 ingress, redirect activation or renewal loop. Ready for review, not Human accepted.

## Staging-CA issuance verified — 2026-09-08 — Ready for review

The approved staging-CA gate is executed and verified on human-assisted evidence; the agent performed only local, registry and non-privileged SSH checks. Both pinned images resolve to `linux/arm64` (nginx `1.30.4-alpine` `aed159…`, certbot `certbot/certbot:v5.8.0` `f70ad…`); both Compose manifests parse. The reviewed `https/` artifacts were installed root-owned to `/opt/sokoladas-staging/releases/section6-https-v1` (SHA-256 matched the Mac copies); baseline evidence was captured under `/root/section6-https-v1-evidence` (saved/runtime IPv4/IPv6, INPUT/OUTPUT/InstanceServices, listeners, sshd -T).

Staging issuance used the isolated `sokoladas-staging_letsencrypt_staging` volume and the shared `acme_webroot` webroot against the Let's Encrypt staging directory. Evidence: `certbot certificates` shows `sokoladas.eu` with identifiers `sokoladas.eu www.sokoladas.eu`, expiry 2026-12-07, `INVALID: TEST_CERT`; `renew --dry-run` reported all simulated renewals succeeded; `docker volume ls` lists only `sokoladas-staging_acme_webroot` and `sokoladas-staging_letsencrypt_staging`, so production `sokoladas-staging_letsencrypt` is absent. The running HTTP bootstrap remained healthy externally (apex/www 503), fresh SSH succeeded, and TCP 443 still timed out.

No production certificate, no TCP 443 publication, no OCI 443 ingress, no proxy replacement and no renewal loop. Ready for review, not Human accepted.

## HTTP bootstrap verified — 2026-09-08 — Ready for review

The authorized HTTP-only group is implemented and verified on human-supplied evidence. Marijus performed all privileged deployment and OCI actions; the agent did not use ubuntu or change sudo access. Earlier entries below describe intermediate checkpoints, not the final state.

- External Mac requests at 12:55:53–54 and 13:01:58 UTC returned 200 and exact `sokoladas-section6-http-v1` content for both apex/www ACME token URLs, 503 with the minimal maintenance body for ordinary requests, and 404 for missing tokens. No redirect or authentication challenge appeared. Maintenance responses include no-store, noindex/nofollow and Retry-After 3600.
- Fresh `ssh -n` through sokoladas.eu returned status 0. TCP 80 connected; TCP 443, 111, 3000, 3001 and 5432 timed out from the Mac. HTTPS timed out with curl status 28. These are source-specific probes paired with on-host inspection, not universal port-isolation proof or evidence of TLS readiness.
- At 12:54:41 UTC the Docker port-80 DNAT and publication ACCEPT counters were zero. At 13:04:54 UTC both were 13 packets / 832 bytes; FORWARD jumps through empty DOCKER-USER and DOCKER-FORWARD counted 126 packets / 11884 bytes, while the original terminal FORWARD REJECT remained zero. Alongside external HTTP results and the recorded rules, this supports the reviewed DNAT → FORWARD → Docker publication path to 172.18.0.2:80. Host INPUT is not its exposure control; no custom DOCKER-USER policy or manual FORWARD accept was added.
- Final baseline comparisons passed for `/etc/iptables/rules.v4`, `rules.v6`, runtime INPUT/OUTPUT/InstanceServices and `sshd -T`. Existing iptables-nft/netfilter-persistent policy and SSH/Oracle rules are unchanged. Docker manages the runtime bridge/NAT rules. Reboot behavior was not tested; future published-port and post-reboot verification remains required.
- Only `sokoladas-staging-proxy-1` was running, healthy with zero failing streak, publishing only `0.0.0.0:80:80`. The only new host listener was docker-proxy IPv4 TCP 80. No TLS, Certbot or application/data service was deployed. The pinned ARM64 image, release directory and bounded local logging are recorded in earlier checkpoints.
- Human cleanup removed only `/.well-known/acme-challenge/s6-http-v1-check` from the shared webroot and verified its absence. External requests to that former token URL returned 404 for both names at **13:06:18 UTC**. The ACME volume and proxy remain; no test token remains at that path.

The OCI screenshot records TCP 80 permission and preserved SSH/ICMP, with no 443 rule. Its OCID/attachment/egress visibility limits remain as recorded below; no new attachment or egress inspection is inferred. Stable addressing and DNS were not reassessed. No certificate issuance, HTTPS activation, rollback execution or reboot is claimed. Section 6 remains open for separately authorized TLS/renewal work; this result is not yet Human accepted.

## HTTP bootstrap local routing and OCI ingress — human evidence 2026-09-08

Human local tests for apex/www returned the exact documented token body, HTTP 503 for ordinary requests and HTTP 404 for a missing token. The documented test token remains present for external verification; cleanup is pending.

The supplied OCI screenshot of `Default Security List for demo-vnc` shows 1–4 of 4 ingress entries: stateful TCP 22 from 0.0.0.0/0, ICMP type 3/code 4 from 0.0.0.0/0, ICMP type 3 from 10.0.0.0/24, and newly added stateful TCP 80 from 0.0.0.0/0 with source ports All. No TCP 443 ingress is shown. The HTTP description is clipped; the resource OCID, subnet attachment and egress are not visible in this screenshot. Earlier attached-list evidence remains recorded; no fresh attachment/egress claim is inferred from this image. External reachability and actual DNAT/FORWARD counter evidence remain pending.

## HTTP bootstrap proxy and firewall gate — human evidence 2026-09-08

Human startup/inspection evidence shows only `sokoladas-staging-proxy-1` running, healthy with zero failing streak and successful health probes through 12:45:23 UTC. Nginx syntax validation passed. Its only publication is `0.0.0.0:80:80`; edge address is `172.18.0.2/16`, gateway `172.18.0.1`, bridge `br-fe32970b2d53`, with no global IPv6 address. Docker local logging retains 10m × 3, compressed. Host listeners add only docker-proxy on IPv4 TCP 80; no TCP 443 listener/publication is shown.

NAT DOCKER now DNATs TCP 80 to 172.18.0.2:80. Filter DOCKER accepts that destination/port on the edge bridge before its unpublished-traffic DROP. FORWARD retains DOCKER-USER (empty) then DOCKER-FORWARD before the original REJECT; edge bridge dispatch/outbound acceptance and masquerade are Docker-generated changes consistent with the reviewed model. No material structural mismatch is identified. External packet traversal still needs counter/request evidence after OCI ingress; rule presence alone is not public-reachability proof.

Human byte/text comparisons succeeded for saved IPv4/IPv6 files, runtime INPUT/OUTPUT/InstanceServices and effective sshd policy against the captured baseline. The earlier session-function failure did not start a container; subsequent self-contained startup did. No OCI change, test-token creation or external HTTP verification is evidenced yet. Next is documented token creation and local route checks; keep OCI unchanged until their evidence is reviewed.

## HTTP bootstrap image/config validation — human evidence 2026-09-08

Marijus pulled the reviewed Nginx digest and supplied image inspection showing linux/arm64. Nonpublished `compose run --rm` validation reported successful nginx.conf syntax/test, Nginx 1.30.4, aarch64, `/usr/bin/wget` and `/bin/grep`. Both temporary containers were removed; `docker ps -a` was empty afterward.

Compose created `sokoladas-staging_acme_webroot` and `sokoladas-staging_edge`. Network inspection reports bridge, IPv6=false, Internal=false, Options={}. These match the approved bootstrap model. Docker bridge/NAT scaffolding may now exist; no publication or actual packet-flow verification is established by these results. Persistent proxy startup, health/publication checks, token and OCI TCP 80 remain pending.

## HTTP bootstrap file staging — human evidence 2026-09-08

Marijus supplied successful file staging from the Mac (copy commands shown at 15:17 local time) and interactive-sudo preparation on the server. Reviewed bootstrap/scripts were copied to `/opt/sokoladas-staging/releases/section6-http-v1`, owned root:root with group/other writes removed. Recursive comparisons against the uploaded copies returned no differences. Compose `config --quiet` succeeded.

Root-only `/root/section6-http-v1-evidence` now holds runtime IPv4/IPv6 snapshots, original saved policy files, INPUT/OUTPUT/InstanceServices listings, listeners and effective sshd configuration for later comparison. The human's final success message confirms the supplied sequence completed. No image pull, container start, token creation or OCI ingress change is evidenced yet. Next gate is pinned-image and nonpublished Nginx validation; firewall and SSH policy remain outside mutation scope.

## HTTP bootstrap privileged preflight — human evidence 2026-09-08

Marijus supplied interactive-sudo preflight output dated 12:06:32 UTC. Host reports sokoladas-demo/aarch64, iptables 1.8.11 nf_tables and enabled netfilter-persistent. Runtime INPUT retains only established/related, ICMP, loopback and TCP NEW 22 accepts before terminal REJECT. FORWARD policy is DROP, with DOCKER-USER then DOCKER-FORWARD ahead of the original REJECT; DOCKER-USER is empty. NAT has Docker hooks and default-bridge masquerade but no publication DNAT. This matches the reviewed pre-publication model, not proof of the future external HTTP path.

No containers or volumes exist; only default bridge/host/none networks are listed. Host listeners are SSH plus local resolver/time and DHCP services; no TCP 80/443 listener. daemon.json retains default storage and local log bounds. Saved host rules intentionally exclude Docker transient chains; their FORWARD policy differs from runtime because Docker owns the runtime change. InstanceServices remains destination-restricted, including UDP 123 to 169.254.169.254; saved/runtime rendering differs by an explicit `-m udp`, not by destination. No policy correction is required.

The supplied systemctl output has pager-truncated long lines; the earlier agent read captured the complete Docker After line. No reboot/persistence test is inferred. Human confirms Serial Console remains available and will execute privileged/OCI operations; agent ubuntu execution and sudo-policy changes are prohibited. Preflight supports proceeding to staged-file and baseline-evidence preparation, with no proxy startup or OCI ingress change yet verified.

## HTTP bootstrap execution preflight — 2026-09-08 — incomplete

Human authorized the revised TCP-80-only bootstrap. At 12:00:17 UTC, agent SSH as marijus through sokoladas.eu with the existing key, BatchMode and strict host-key checking succeeded; the server reported sokoladas-demo and aarch64. `sudo -n true` failed with `interactive authentication is required`. No privileged checks or configuration changes followed. The readable daemon.json retains default data-root and bounded local logs; netfilter-persistent reports enabled. Readable unit definitions place netfilter-persistent before network-pre and Docker after network-online; no reboot behavior is claimed.

Execution awaits an approved usable sudo path, confirmation that independent Serial Console recovery remains available, and coordination of the OCI Console step. No OCI connector/CLI/local OCI config is available to this agent. No files were copied to the host, no container/image/token was created, no port/rule/service changed, and no external HTTP or forwarding verification is claimed. This is incomplete execution evidence, not successful bootstrap completion.

## Hostname SSH identity — human-verified 2026-09-08 — Ready for review

Marijus reports that this command successfully connected to `sokoladas.eu (79.76.117.246)` using the existing SSH key:

```sh
ssh -i ~/.ssh/id_ed25519_oracle marijus@sokoladas.eu
```

The presented ED25519 server host-key fingerprint was:

```text
SHA256:Qt7o7y7xOUccDssX6R5xGkOfQ0oKGaEYnQlsZ+0usLI
```

OpenSSH identified it as the same host key already known for both former ephemeral address `152.70.25.153` and reserved address `79.76.117.246`. This is additional human evidence that the canonical hostname resolves to and reaches the intended existing sokoladas-demo server: successful SSH and verified host identity support the conclusion, not DNS alone. The key path identifies the existing client key; no private key material is recorded.

This supplements the earlier address-only SSH and DNS evidence, including the previously unsupplied exact fingerprint. It does not establish HTTP/HTTPS reachability, certificate issuance, application deployment or fresh independent recovery testing. No independent agent SSH/DNS check was performed; Section 6 remains open and the next bootstrap approval scope is unchanged.

## DNS prerequisite — human-verified 2026-09-08 — Ready for review

Marijus manually changed Namecheap records to `A @ 79.76.117.246` and `CNAME www sokoladas.eu`, removing `CNAME www parkingpage.namecheap.com` and `URL Redirect @ http://www.sokoladas.eu/`.

Human-supplied Mac verification:

```text
$ dig +short sokoladas.eu A
79.76.117.246
$ dig +short www.sokoladas.eu A
sokoladas.eu.
79.76.117.246
$ dig +short www.sokoladas.eu AAAA
sokoladas.eu.
$ dig +short sokoladas.eu AAAA
[no output]
```

The apex resolves to the reserved OCI IPv4, and www aliases to the apex and the same IPv4. The AAAA answers contain no IPv6 address for either hostname; the www response is the CNAME, not an IPv6 address. DNS is ready for the planned IPv4-only HTTP/HTTPS bootstrap on this human evidence. The accidental `dig ... AAA` command is excluded from verification evidence.

DNS prerequisite is complete. These are results from the human's Mac resolver at the time of testing, not independent agent queries or proof of every worldwide cache. TTL, authoritative-server/CAA/DNSSEC checks and exact timestamps were not supplied; none are invented. This evidence does not establish HTTP reachability, firewall changes, certificate issuance or Nginx deployment. Earlier no-DNS-change statements describe the preceding address-cutover step. Section 6 remains open; sokoladas.online stays outside scope.

## Reserved public IPv4 — human-executed 2026-09-08 — Ready for review

Marijus reports successful creation of OCI Reserved Public IPv4 resource **`sokoladas-public-ip`**, address **`79.76.117.246`**, replacing the former ephemeral **`152.70.25.153`** on sokoladas-demo. The new reserved public address is assigned to primary private IPv4 **`10.0.0.52`**; OCI IP Administration displays `79.76.117.246 (Reserved)` on that private IP. Guest private IPv4 remains `10.0.0.52`.

SSH to `marijus@79.76.117.246` succeeded using the existing key. SSH identified the same ED25519 server host key previously known for `152.70.25.153`, supporting continuity of server identity across the address change. The exact fingerprint and execution time were not supplied; this is human evidence, not an independent agent test.

**UI inconsistency:** the same OCI IP Administration row displays `IP lifetime: Ephemeral` alongside public address `79.76.117.246 (Reserved)`. Record both labels without reclassifying the public address: the human-created reserved resource and explicit `(Reserved)` public-address label establish the reported reserved assignment. The scope/cause of the lifetime field has not been verified; no corrective live action is inferred.

Marijus reports no DNS, firewall, Nginx, Docker or application changes in this step. Stable-address creation/assignment and new-address SSH verification are complete on this evidence. Section 6 DNS/HTTPS work remains unfinished. No new pricing evidence, OCIDs, outbound-connectivity test, fresh sudo/ubuntu/Serial Console test or broader port scan was supplied; do not infer these from successful SSH. Recorded historical recovery evidence remains unchanged. Do not use the released ephemeral address for future access or DNS rollback.

This record supersedes earlier current-address/ephemeral descriptions; dated historical observations below retain their original addresses. See the [Section 6 plan and remaining work](domain-https-plan.md). This documentation reconciliation performed no live access/change, commit or push.

## Docker host installed and verified — 2026-09-08 — Human accepted

The owner approved the Section 4 rootful Docker target and live installation. Implemented on `sokoladas-demo` (`152.70.25.153`) with preflight at **10:01:35 UTC**, repository setup at **10:02:10–10:02:15 UTC**, package installation at **10:02:39–10:02:56 UTC**, and verification through **10:04:34 UTC**. Administrative commands ran through ubuntu SSH with sudo; no credentials, sudoers, group memberships or SSH configuration were changed. This result supersedes the earlier assessment's absent-runtime state and pending target choices. Marijus explicitly accepted the Section 4 Docker host implementation and its documentation on 2026-09-08. It is Human accepted.

### Access, prerequisites and LXD disposition

Fresh marijus SSH succeeded before installation and again at 10:03:52 UTC afterward. An attempted retained shell had closed local stdin, so it is not counted as a continuously usable fallback; fresh connections verified access. Ubuntu SSH/sudo also worked before and after installation. The owner's September 7 tested OCI Serial Console path remains the recorded independent recovery method: dedicated console key/connection, then interactive marijus login. No new console or arbitrary boot-repair test is claimed.

Rechecked Ubuntu **26.04.1 LTS / resolute**, kernel `7.0.0-1010-oracle`, `aarch64`, dpkg `arm64`, approximately 40 GiB free root ext4 space, no existing Docker/data/config paths, and no installed conflicting packages. The only prior APT source was ubuntu.sources and /etc/apt/keyrings was empty. Repository refresh authenticated the Docker InRelease through the scoped key without errors. Simulation and installation both reported **exactly five new packages, zero upgrades and zero removals**. The install fetched 77.1 MB and estimated 334 MB added package storage; no optional rootless extras, pigz, alternative runtime or management layer was installed.

The final read-only LXD preflight at **09:58:41–09:59:07 UTC** established only `lxd-installer` 14ubuntu0 and `lxd-agent-loader` 0.13ubuntu0. `lxd-installer.socket` is enabled/active/listening, root:lxd 0660, at its distinct `/run/lxd-installer.socket`; no installer service instance runs. `lxd-agent.service` is static/inactive. No LXD runtime, bridge, container namespace, data mount/path or TCP/UDP listener was found. The wrappers can activate snap installation and were not invoked. No Docker/containerd file, socket or declared package conflict exists. A removal simulation would also remove ubuntu-server because it depends on lxd-installer; removing about 53 KiB of package payload provides no Docker benefit. Both packages and their files were retained unchanged; post-install `dpkg --verify` returned no differences and the socket remains active. No removal or deactivation occurred.

### Installed configuration and versions

| Package | Installed version | Architecture |
|---|---|---|
| docker-ce | `5:29.8.0-1~ubuntu.26.04~resolute` | arm64 |
| docker-ce-cli | `5:29.8.0-1~ubuntu.26.04~resolute` | arm64 |
| containerd.io | `2.3.4-2~ubuntu.26.04~resolute` | arm64 |
| docker-buildx-plugin | `0.37.0-1~ubuntu.26.04~resolute` | arm64 |
| docker-compose-plugin | `5.5.1-1~ubuntu.26.04~resolute` | arm64 |

Source: `https://download.docker.com/linux/ubuntu`, suite resolute, component stable, architecture arm64; key downloaded from `/linux/ubuntu/gpg` to `/etc/apt/keyrings/docker.asc`. Both key and `/etc/apt/sources.list.d/docker.sources` are root:root 0644. The existing Ubuntu sources remain in place. The deb822 source contents are:

```text
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: resolute
Components: stable
Architectures: arm64
Signed-By: /etc/apt/keyrings/docker.asc
```

Created `/etc/docker/daemon.json` (root:root 0644) **before package auto-start**, with the approved bounded local policy:

```json
{
  "data-root": "/var/lib/docker",
  "log-driver": "local",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "compress": "true"
  }
}
```

`python3 -m json.tool` passed before installation and `dockerd --validate --config-file=/etc/docker/daemon.json` returned `configuration OK` afterward. Container stdout/stderr rotation is approximately 30 MiB uncompressed per container plus overhead; it does not cap images, volumes, application log files or host-wide disk use. Journald policy was not changed. Application containers created later inherit this policy unless explicitly overridden.

Storage uses `/var/lib/docker` and the package-default `/var/lib/containerd`, on the existing ext4 boot filesystem. Docker reports **overlayfs**, `io.containerd.snapshotter.v1`, systemd cgroup driver, cgroup v2, AppArmor and seccomp. No legacy overlay2 override, separate volume or custom containerd configuration was introduced. The packaged `/etc/containerd/config.toml` disables CRI and leaves root/state defaults; `containerd config dump` resolved root `/var/lib/containerd` and state `/run/containerd`. That read-only command emitted a legacy configuration migration warning for the package's versionless file; it succeeded, services are healthy, and no migration rewrite was performed. Post-cleanup `du` reported 240K Docker and 268K containerd metadata; `df` reported 5.2G used, 39G available, 12% used on root.

Administration remains **sudo Docker**. The package-created docker group is GID 987 with no supplementary members; marijus remains in marijus/sudo/users only. Socket ownership/mode is root:docker 0660. A fresh marijus `docker -H unix:///var/run/docker.sock ps` returned permission denied, as expected. Rootless Docker and docker-group grants were not selected. Existing ubuntu passwordless recovery access remains; this scoped execution does not grant general future agent/deployment authority.

The approved restart guidance remains `unless-stopped` for future long-running Compose services and `"no"` for one-shot/migration/test containers. No application has been deployed and no container restart policy is implied by enabling the Docker service. Future application readiness, retries and persistence tests remain deployment work.

### Executed installation and verification

The earlier assessment below records the exact repository setup and configuration commands; they were executed with root privileges through sudo, without overwriting pre-existing Docker configuration. After `apt-get update` and review of the identical `--simulate` transaction, the actual installation used:

```bash
sudo apt-get --yes --no-install-recommends --no-remove install \
  'docker-ce=5:29.8.0-1~ubuntu.26.04~resolute' \
  'docker-ce-cli=5:29.8.0-1~ubuntu.26.04~resolute' \
  'containerd.io=2.3.4-2~ubuntu.26.04~resolute' \
  'docker-buildx-plugin=0.37.0-1~ubuntu.26.04~resolute' \
  'docker-compose-plugin=5.5.1-1~ubuntu.26.04~resolute'
```

Package scripts enabled and started Docker/containerd automatically; no extra enable/start/restart was necessary. debconf fell back to its noninteractive frontend in the SSH session and completed successfully; no unrelated service restart was requested by needrestart. The exact versions are a recorded installation choice, not permanent apt holds.

| Verification | Result |
|---|---|
| `systemctl is-enabled/is-active` | docker.service, docker.socket and containerd.service all enabled/active; both services running with ExecMainStatus 0 |
| `sudo docker version` | Client/server 29.8.0, both linux/arm64; containerd v2.3.4; bundled runc 1.5.1 |
| `sudo docker info` | aarch64, `/var/lib/docker`, local logging, overlayfs containerd snapshotter; no application workload |
| `sudo docker compose version` | v5.5.1 |
| `sudo docker buildx version` | v0.37.0 |
| Official ARM64 test | `hello-world:latest`, `--platform=linux/arm64 --network=none --restart=no`, named section4-hello; exited 0, arm64v8 success output |
| Test inspection | Image linux/arm64; inherited LogConfig exactly local with compress=true, max-file=3, max-size=10m; no port bindings |
| Cleanup | `docker rm section4-hello`, then `docker image rm hello-world:latest` succeeded. `docker system df`: zero images, containers, volumes and build cache |
| Health | dpkg audit empty, zero failed units, no warning-or-higher Docker/containerd journal entries in the inspected installation interval |
| Access / listeners | Fresh marijus and ubuntu SSH succeeded; privileged ss inventory unchanged: wildcard TCP 22 only, existing loopback DNS/chrony and interface-bound DHCP. No new public listener or Docker TCP API |

The temporary official image digest was `hello-world@sha256:5dd0d3e6e255913fc30f90b9f2b1d359cc2cbdb48090cc4b65f1676e203243cc`; it was removed, not retained as deployment state. No Alpine or application image was needed. Successful registry pull verifies the daemon's outbound path; the network-none test does not verify container bridge egress or DNS.

### Docker-managed network changes and preserved policy

Docker's approved normal startup changed **runtime networking**: IPv4 ip_forward 0 → 1, docker0 `172.17.0.1/16`, IPv4 FORWARD default ACCEPT → DROP, and DOCKER-USER/DOCKER-FORWARD jumps before the existing unconditional FORWARD REJECT. Docker added its bridge filtering and IPv4 masquerade rule; no published-port DNAT rules exist. IPv6 gained Docker forwarding/NAT chain scaffolding; host INPUT/OUTPUT/FORWARD defaults remain ACCEPT and enp0s6 remains link-local-only. These observed automatic changes must not be described as “no firewall changes.” No manual firewall policy edit, flush, save, restore or web-port opening occurred.

The host INPUT sequence, OUTPUT InstanceServices jump and InstanceServices rules were unchanged, including destination-restricted UDP 123. Original FORWARD REJECT remains. Before/after SHA-256 equality verified saved files and SSH hardening:

| File | Unchanged SHA-256 |
|---|---|
| `/etc/iptables/rules.v4` | `02bef6508e4f471a2d6ffffe849c3ad04ad87c9a101ab4785c18054d041d63b2` |
| `/etc/iptables/rules.v6` | `3036493195a2ecb860f6754089857d1b75e21f24b87187d63ee8346a147b4eb5` |
| `/etc/ssh/sshd_config.d/90-sokoladas-hardening.conf` | `aac5c7c061dcf3e61d7c38bcab5506d8b75a1ac597fc1184ccba3c01499b7b10` |

Existing OCI/default/link-local routes remain; no OCI, DNS, SSH policy or Section 6 exposure changes were made. The accepted Section 3 baseline remains closed. **Section 4 retains its future container forwarding/published-port verification task**: this installation verifies the empty host baseline, not application port privacy under a future Compose deployment. Evaluate OCI rules, Docker forwarding/NAT and actual port bindings together then. No reboot, firewall reload, external all-port scan, container DNS/egress test, log-rotation stress test or rollback was performed; enabled units are not proof of tested post-reboot behavior.

All requested installation checks passed. The implementation and documentation are Human accepted as of 2026-09-08. This acceptance supersedes the earlier assessment/proposal review status without changing its historical evidence. Docker-managed runtime bridge/NAT rules and required future published-port verification remain recorded above. Acceptance involved repository checks only, with no additional live changes; the owner authorized a commit but no push.


## Section 4 Docker host assessment and proposed implementation — 2026-09-08 — Ready for review

**Historical assessment and proposal, preceding the approved installation above; Section 4 retains deployment verification work.** No runtime was installed or invoked, and no service, repository, configuration, group, or firewall was changed. The proposed target and commands below require a subsequent human decision and scoped live authorization.

### 1. Observed state

Authorized SSH inspection of `sokoladas-demo` at `152.70.25.153`, September 8 **09:34:12–09:36:49 UTC**. Initial login was marijus using the established Oracle key with BatchMode, IdentitiesOnly, strict host-key checking, and host-key updates disabled. `sudo -n -l` required interactive authentication. Marijus then explicitly authorized using ubuntu's passwordless sudo for these read-only checks; `sudo -n` succeeded there. No authentication settings changed. Local sandbox/network retries were approved. Normal SSH/sudo audit logging and access-time effects were not suppressed.

| Area | Established observation |
|---|---|
| OS / architecture | Ubuntu 26.04.1 LTS, `resolute`; kernel `7.0.0-1010-oracle`, `aarch64`; dpkg architecture `arm64`, no foreign architectures returned |
| Runtime packages / commands | No installed Docker Engine/CLI, containerd, runc, Podman, crun, Buildah, Incus, Kubernetes runtime, RootlessKit, slirp4netns, or uidmap package in the scoped dpkg listing. PATH checks found no docker/dockerd/containerd/ctr/runc/podman/crun/nerdctl/buildah/incus/k3s/kubelet/newuidmap/newgidmap/rootlesskit/slirp4netns |
| Services / sockets | docker.service, docker.socket, containerd.service, podman.service and podman.socket are `not-found`/inactive. No corresponding system unit files, marijus user units, runtime processes, or runtime Unix sockets found. The process-name substring match `runcommand` belongs to OCI's agent, not runc |
| LXD exception | `lxd-installer` **14ubuntu0** and `lxd-agent-loader` **0.13ubuntu0** installed; matching versions available from Ubuntu resolute/main. `/usr/sbin/lxc` and `/usr/sbin/lxd` belong to lxd-installer. `lxd-installer.socket` is enabled/active/listening at `/run/lxd-installer.socket`, mode 0660 root:lxd; activation invokes the snap installer. `lxd-agent.service` is static/inactive. No LXD snap/data/runtime observed. Installer commands and socket were deliberately not invoked |
| Snap / custom locations | Snap lists only core18, oracle-cloud-agent, snapd. `/usr/local/bin`, `/usr/local/sbin`, `/opt`, `/srv` empty. No Docker/Podman rootless data/config or Docker user service at the inspected standard paths under root, ubuntu, opc, or marijus; no `bin/docker` or `.local/bin/docker` there |
| Docker storage / config | Privileged checks confirm `/var/lib/docker`, `/var/lib/containerd`, `/var/lib/containers`, `/var/snap/docker`, `/var/snap/lxd/common/lxd`, `/etc/docker`, `/etc/containerd`, `/etc/containers`, `/run/docker.sock`, `/run/containerd` absent |
| Filesystem capacity | `/var/lib` and `/home` share `/dev/sda1`, ext4, mounted `/`; disk 46.6 GiB, root partition 45.6 GiB. `df -hT` rounds root to 45G, 4.8G used, 40G available, 11% used. 5,831,991 free inodes, 3% used. No separate Docker/data filesystem observed |
| Administration | marijus UID 1002, groups marijus/sudo/users; ubuntu UID 1001, groups ubuntu/adm/cdrom/sudo/dip/lxd. No docker/podman/containerd group returned. Existing ubuntu recovery access already provides passwordless root control; this assessment's permission does not extend to future mutations |
| Rootless prerequisites | cgroup v2; systemd 259.5; dbus-user-session installed. marijus has 65,536 subordinate UIDs and GIDs starting at 231072; `Linger=no`. User namespaces enabled, maximum 43,362; AppArmor restriction enabled. AppArmor enabled and `/etc/apparmor.d/rootlesskit` allows userns for `/usr/bin/rootlesskit`. uidmap/helpers and rootless runtime missing. user@1002.service reports delegation of cpu/memory/pids, but was inactive in the later session; its live cgroup path was absent, so effective runtime delegation remains untested. Unprivileged ports begin at 1024 |
| Kernel prerequisites | Kernel config includes namespaces, user namespaces, cgroups, memory/cpuset controls, seccomp and netfilter; overlayfs, bridge and veth built as modules. No module loading or container execution tested |
| Existing network policy | iptables 1.8.11 uses nf_tables; netfilter-persistent enabled. Loaded FORWARD policy ACCEPT with unconditional REJECT rule; IPv4 forwarding is 0. Docker startup will change forwarding/NAT/bridge state and needs separate approval and verification; the accepted Section 3 baseline stays closed |
| Journald / syslog | Merged journald config has no explicit size/retention overrides; packaged commented defaults include Storage=persistent, rate limit 10,000/30s and no maximum retention age. Active vendor override `ForwardToSyslog=yes`; rsyslog active. Persistent and runtime journal directories exist. Root `journalctl --disk-usage`: 48M; unprivileged 11.6M was only the readable subset. Journal directory uses about 49M. No Docker-specific journald constraint configured |
| Package health | No held packages or dpkg audit findings; zero failed systemd units. No policy-rc.d file. Read-only APT/dpkg history search returned no Docker/containerd/runc/Podman/LXD install/remove/upgrade match in retained logs; only current September 6 logs exist |

**Was Docker data-root ever created?** It is absent now and no evidence of earlier creation/installation was found in the retained logs or standard paths. This cannot establish “never”: deleted directories and missing older logs leave no guaranteed trace. No full-disk forensic search, arbitrary executable scan, private Docker credential/context inspection, or exhaustive custom-path audit was performed.

APT configuration: `/etc/apt/sources.list` is comments only. The only file in sources.list.d is `ubuntu.sources`, with `resolute`, `resolute-updates`, `resolute-backports` at `http://eu-frankfurt-1-ad-3.clouds.archive.ubuntu.com/ubuntu/` and `resolute-security` at `http://security.ubuntu.com/ubuntu`; all use main/universe/restricted/multiverse and `/usr/share/keyrings/ubuntu-archive-keyring.gpg`. `/etc/apt/keyrings` is empty; no Docker source/key exists in inspected locations. trusted.gpg is absent; trusted.gpg.d contains the Ubuntu 2012 cdimage and 2018 archive keys. Shared keyrings are Ubuntu/cloud-image/Ubuntu Pro keys. Only Ubuntu Pro ESM preference files exist (priority 510); no Docker pin. Key contents/fingerprints were not audited. No `apt update` ran; APT policy is from existing cache, with update/security InRelease timestamps on September 8.

Installed prerequisites and available source versions agree in APT policy; this identifies available origins, not historical download provenance:

| Package | Installed version | Available matching origin |
|---|---|---|
| curl | 8.18.0-1ubuntu2.4 | resolute-updates/security main |
| ca-certificates | 20260601~26.04.1 | resolute-updates/security main |
| libc6 | 2.43-2ubuntu2.3 | resolute-updates/security main |
| libseccomp2 | 2.6.0-2ubuntu5 | resolute main |
| apparmor | 5.0.2-0ubuntu1~26.04.1 | resolute-updates main |
| dbus-user-session | 1.16.2-2ubuntu4 | resolute main |
| iptables / nftables | 1.8.11-2ubuntu3 / 1.1.6-1 | resolute main |

Docker CE/CLI have no installed version/candidate; no official plugin/containerd.io candidate was returned. Ubuntu alternatives are available but uninstalled: docker.io 29.1.3-0ubuntu4.1, containerd 2.2.2-0ubuntu1.1, runc 1.4.0-0ubuntu1, podman 5.7.0+ds2-3build1. No observed package conflict needs removal. LXD installer presence is an incidental activation risk, not evidence that Docker requires its removal; retain it for this proposal and avoid invoking it.

### 2. Compatibility findings

Checked Docker's public sources on September 8. The [official Ubuntu installation guide](https://docs.docker.com/engine/install/ubuntu/) explicitly lists Ubuntu Resolute 26.04 LTS and arm64. Linux `aarch64` maps to APT `arm64`; use suite **resolute**, never substitute noble. Existing libc6/libseccomp meet the published dependencies. Actual runtime compatibility with this OCI kernel still needs installation tests.

The [official Resolute stable ARM64 package index](https://download.docker.com/linux/ubuntu/dists/resolute/stable/binary-arm64/Packages), downloaded locally over HTTPS without touching server APT state, includes these concrete proposed versions:

| Package | Published arm64 version |
|---|---|
| docker-ce / docker-ce-cli | `5:29.8.0-1~ubuntu.26.04~resolute` |
| containerd.io | `2.3.4-2~ubuntu.26.04~resolute` |
| docker-buildx-plugin | `0.37.0-1~ubuntu.26.04~resolute` |
| docker-compose-plugin | `5.5.1-1~ubuntu.26.04~resolute` |
| docker-ce-rootless-extras (alternative only) | `5:29.8.0-1~ubuntu.26.04~resolute` |

This establishes published release/architecture packages, not an installed or signature-verified transaction. Future APT must authenticate the repository metadata and simulate exact dependencies. containerd.io conflicts with distro containerd/runc and bundles the needed runtime; do not install both. Compose is the `docker compose` CLI plugin, regardless of its current major version; no standalone legacy docker-compose. Buildx supports future container builds without a host Node.js/pnpm runtime. No convenience script, Docker Desktop, management layer, or alternate orchestrator is proposed.

### 3. Decisions requiring human approval

**Recommended direction: rootful Docker with human `sudo docker ...`, no added docker-group members.** This is a proposal, not an approved privilege or deployment policy.

| Model | One administrator / one VM | AI access and future scripts | Assessment |
|---|---|---|---|
| Rootful, `sudo docker ...` | Straightforward system service, conventional Compose and ports 80/443; deliberate human sudo step | General Docker access remains root-equivalent when granted. Avoid NOPASSWD Docker rules. Human can run reviewed deployment scripts with sudo; unattended deployment authorization remains a later decision | Recommended for current scope and minimal operation |
| Rootful, marijus in docker group | Saves typing/password prompts, same daemon and networking | Every process/agent with that login gains continuous root-equivalent Docker control. Writable Compose files, host mounts, privileged containers and socket access defeat naive command allowlists | Convenience does not justify the standing grant here |
| Rootless Docker | Technically realistic with this kernel, ext4, cgroup v2 and subordinate IDs; adds uidmap, rootless extras, user service and lingering | Reduces daemon host-root privilege, but an agent under the same account still controls that account's containers, data and files. Dedicated non-sudo deployment identity could improve separation later | Viable alternative if isolation is prioritized; requires a revised installation plan and deliberate low-port/network/resource testing |

Docker documents [root-level docker-group privileges](https://docs.docker.com/engine/install/linux-postinstall/). `sudo` is an operational gate, not an AI security sandbox: marijus has broad sudo entitlement and cached credentials may matter; ubuntu's passwordless recovery path already exists. Tool authorization and credential access must remain scoped. Do not automatically reuse ubuntu for future deployment or grant agents a Docker socket. A future unattended script needs an explicit trust model; unrestricted Docker/Compose under sudo is effectively host-root access even if wrapped in a script.

[Rootless prerequisites](https://docs.docker.com/engine/security/rootless/) require uidmap helpers and subordinate IDs. [Rootless operational guidance](https://docs.docker.com/engine/security/rootless/tips/) covers lingering and privileged ports; this VM's 1024 threshold means binding 80/443 needs a separately approved capability/port approach. Keep the reverse proxy in a container; do not add a host proxy merely to work around this choice. [Ubuntu rootless guidance](https://docs.docker.com/engine/security/rootless/troubleshoot/) supports the packaged AppArmor profile, already present here; do not disable AppArmor/user-namespace restrictions. Rootless container AppArmor limitations and resource/network behavior require validation; profile presence alone does not prove a working rootless daemon.

Other proposed choices to approve together:

- **Storage:** retain local ext4 on the existing boot disk; no extra volume/cost or partition change. Explicit Docker data-root `/var/lib/docker`; retain containerd's `/var/lib/containerd`. Fresh Engine 29 uses the [containerd image store](https://docs.docker.com/engine/storage/containerd/); images/snapshots are there, while Docker volumes/config remain under Docker's root. [Changing data-root does not relocate containerd](https://docs.docker.com/engine/daemon/). Keep the default snapshotter; do not force legacy overlay2. Use named volumes for later persistent services after backup decisions; image layers/build cache/logs share the roughly 40 GiB free space and are not a backup. Review disk usage before builds, retain headroom, and plan capacity once image/data sizes are known. No automated prune or data deletion.
- **Logs:** `local`, `max-size=10m`, `max-file=3`, compression enabled, about 30 MiB uncompressed rotation budget per container plus overhead. This limits stdout/stderr logs, not application files, images, volumes, or total host usage. Read via `docker logs`; no external logrotate over Docker files. The [local driver](https://docs.docker.com/engine/logging/drivers/local/) supports rotation/compression. Daemon service logs still go to journald; leave existing journal policy for now, with host-wide retention under maintenance. No extra log collector. [Logging defaults affect newly created containers](https://docs.docker.com/engine/logging/configure/); retained delivery mode is blocking, so backpressure remains possible.
- **Restart behavior:** future long-running Compose services use `restart: unless-stopped`, preserving intentional stops; one-shot migrations and verification containers use `restart: "no"`. Restart policy is per container, not a daemon-wide restart setting. Docker/containerd start at boot. [Restart policies](https://docs.docker.com/engine/containers/start-containers-automatically/) do not restart a merely unhealthy but running process or replace application retry/readiness logic. No systemd unit per application container.
- **Network/startup:** approve rootful package service auto-start, boot enablement and Docker-managed bridge/NAT/forwarding changes. Keep the iptables backend with the existing iptables-nft tools, preserve InstanceServices, and publish no ports during initial installation. Do not set `iptables=false`, open OCI/web ports, flush rules, or save Docker's transient rules through netfilter-persistent. [Docker inserts forwarding chains](https://docs.docker.com/engine/network/firewall-iptables/); inspect their ordering against the host's unconditional FORWARD REJECT. Verify again after any firewall reload/reboot in a separately approved test. A network conflict is a stop-and-review finding, not permission to remove the REJECT.

### 4. Exact proposed live steps — NOT EXECUTED

These steps implement only the recommended rootful target after approval. They are review material, not an executable repository bootstrap yet. Run as the human administrator on `sokoladas-demo`; use Bash and stop on errors. Before access-affecting installation, retain a working marijus session, confirm the ubuntu fallback and owner-tested OCI Serial Console remain available and understood. The recorded recovery evidence is dated September 7, not a fresh console test. If recovery is unavailable, do not proceed. Success includes a fresh marijus SSH session afterward.

**A. Recheck identity, conflicts, storage and recovery before any mutation.** Review output; changed facts require revising this plan. Capture firewall evidence outside public logs, without credentials. Do not rewrite saved rules.

```bash
set -euo pipefail
hostname
. /etc/os-release
test "$ID" = ubuntu
test "$VERSION_CODENAME" = resolute
test "$(dpkg --print-architecture)" = arm64
sudo -v
df -hT /var/lib
df -i /var/lib
sudo iptables-save
sudo ip6tables-save
sudo cat /etc/iptables/rules.v4 /etc/iptables/rules.v6
ip -4 route
sysctl net.ipv4.ip_forward
systemctl --failed --no-pager
dpkg-query -W -f='${binary:Package} ${db:Status-Abbrev} ${Version}\n' \
  | grep -E '^(docker|containerd|runc|podman|crun)' || true
```

No conflicting package is currently installed. If a conflict appears, stop for its workload/removal review; there is no blanket uninstall step. Confirm default Docker address pools do not collide with any newly added local/VPN routes. Existing OCI 10.0.0.0/26 does not itself conflict with the conventional Docker 172.17.0.0/16 bridge; verify the allocated subnet afterward.

**B. Add only Docker's scoped key/repository, refresh metadata and review the exact install simulation.** Existing curl/ca-certificates are sufficient. Fail if destination configuration already exists; do not overwrite a later setup. No global apt upgrade, repository substitution or automatic removals.

```bash
sudo test ! -e /etc/apt/keyrings/docker.asc
sudo test ! -e /etc/apt/sources.list.d/docker.sources
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod 0644 /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<'SOURCES'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: resolute
Components: stable
Architectures: arm64
Signed-By: /etc/apt/keyrings/docker.asc
SOURCES
sudo apt-get update
apt-cache policy docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
engine_version='5:29.8.0-1~ubuntu.26.04~resolute'
containerd_version='2.3.4-2~ubuntu.26.04~resolute'
buildx_version='0.37.0-1~ubuntu.26.04~resolute'
compose_version='5.5.1-1~ubuntu.26.04~resolute'
sudo apt-get --simulate --no-install-recommends install \
  "docker-ce=$engine_version" "docker-ce-cli=$engine_version" \
  "containerd.io=$containerd_version" "docker-buildx-plugin=$buildx_version" \
  "docker-compose-plugin=$compose_version"
```

Stop on repository authentication errors, missing versions, removals or unexpected dependency changes. Review the displayed download/disk budget and arm64 origins before installation. Exact versions make this transaction reviewable, not a permanent hold; future upgrades need deliberate review. `--no-install-recommends` avoids adding unused rootless extras and other optional packages; installed AppArmor/certificates remain available. Buildx and Compose are explicitly selected despite being recommendations in some package metadata.

**C. Configure logging/storage before package auto-start, then install.** This creates new configuration only. Validate JSON before installation; daemon semantic validation follows once the binary exists. Package installation may start services and modify kernel networking immediately; that behavior must be part of live approval.

```bash
sudo test ! -e /etc/docker
sudo install -d -m 0755 /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'JSON'
{
  "data-root": "/var/lib/docker",
  "log-driver": "local",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "compress": "true"
  }
}
JSON
sudo chmod 0644 /etc/docker/daemon.json
python3 -m json.tool /etc/docker/daemon.json >/dev/null
sudo apt-get --no-install-recommends install \
  "docker-ce=$engine_version" "docker-ce-cli=$engine_version" \
  "containerd.io=$containerd_version" "docker-buildx-plugin=$buildx_version" \
  "docker-compose-plugin=$compose_version"
sudo dockerd --validate --config-file=/etc/docker/daemon.json
sudo systemctl enable --now containerd.service docker.service
```

Use the same Bash session for B/C variables. No usermod, sudoers change, Docker TCP listener, custom containerd configuration or firewall rewrite is part of this proposal.

**D. Verify installation, native ARM64 and the new network state.** These future container commands create/pull data and run workloads; they were not used in the assessment. Obtain approval for both named smoke-test containers, retaining them stopped for inspection rather than silently deleting them.

```bash
dpkg-query -W -f='${binary:Package} ${Version} ${Architecture}\n' \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl is-active docker.service containerd.service
sudo systemctl is-enabled docker.service containerd.service
sudo docker version
sudo docker info
sudo docker compose version
sudo docker buildx version
sudo stat -c '%a %U:%G %n' /run/docker.sock
getent group docker
sudo docker run --name section4-hello --restart=no --network=none \
  --platform=linux/arm64 hello-world:latest
sudo docker run --name section4-arm64 --restart=no --network=none \
  --platform=linux/arm64 alpine:latest uname -m
sudo docker image inspect hello-world:latest alpine:latest \
  --format '{{.Os}}/{{.Architecture}} {{json .RepoDigests}}'
sudo docker inspect section4-hello section4-arm64 \
  --format '{{.Name}} exit={{.State.ExitCode}} log={{json .HostConfig.LogConfig}} restart={{json .HostConfig.RestartPolicy}} ports={{json .HostConfig.PortBindings}}'
sudo docker logs section4-hello
sudo docker ps -a
sudo docker system df
sudo du -sh /var/lib/docker /var/lib/containerd
df -hT /var/lib
sudo docker network inspect bridge
sudo iptables-save
sudo ip6tables-save
sysctl net.ipv4.ip_forward
sudo ss -lntup
sudo journalctl -u docker.service -u containerd.service --since '15 minutes ago' --no-pager
systemctl --failed --no-pager
```

Expect both test exits 0, native `aarch64`, image `linux/arm64`, daemon ARM64, expected package versions, `local` logging with the proposed options, data-root `/var/lib/docker`, and the containerd snapshotter reported by Docker info. Record actual pulled digests; floating tags are scoped smoke-test inputs, not deployment pins. No emulation/binfmt installation. Socket must not be world accessible (normally root:docker 0660), docker group must not include marijus/ubuntu, and no TCP Docker API or application port should appear. No-group access can be checked with `docker -H unix:///var/run/docker.sock ps` as marijus: permission denied is the expected boundary.

Review firewall deltas and bridge routes; verify InstanceServices and saved files unchanged, SSH still works in a fresh session, and no unexpected failed units. The smoke tests use no network and do not verify container egress, port publishing, or restart-after-reboot behavior. Those remain explicit Section 4 checks: approve a concrete bridge/DNS/egress and private/published-port test with the actual intended OCI/host path, and a maintenance-window reboot/reload test if persistence is to be claimed. Do not open 80/443 early to complete Docker installation. Inspect configured rotation now; an actual rotation stress test and application restart/readiness tests require later scoped workloads.

### 5. Rollback and removal considerations — NOT AUTHORIZED

Before the first install, the relevant daemon/source/key paths are absent; record if that changes. A failed transaction can leave packages, services, config and networking partly installed. Inspect `dpkg --audit`, service status and sanitized logs first. Do not treat stopping Docker as restoration of the previous host firewall/forwarding state.

A separately approved withdrawal would first inventory containers/volumes and preserve any data that now matters, then stop/disable docker.service **and docker.socket** plus containerd.service only after checking consumers. Simulate removal of the five explicitly installed packages; review effects before removing them. Do not purge unrelated packages, autoremove, delete data roots, prune volumes or flush firewall rules. Package removal does not automatically remove `/var/lib/docker` or `/var/lib/containerd`; their preservation is intentional. Removing the new source/key/config or smoke-test containers is a separately scoped cleanup, not a blanket command in this plan. Snapshotter/data-format changes make arbitrary downgrade unsafe; verify version compatibility and use backups when needed.

Recheck SSH, service state, forwarding and the complete OCI/host path after withdrawal. Never restore old saved rules blindly or save transient Docker chains with netfilter-persistent. Keep the documented ubuntu/Serial Console recovery path available. No rollback, stop/start, removal or reboot was tested during this assessment.

Verification of this documentation: cross-checked package/PATH evidence with systemd, sockets, snap and protected standard paths; distinguished LXD installer activation from a runtime; checked filesystem and privilege prerequisites; compared official Ubuntu support with the published ARM64 package index; reviewed proposed commands, JSON, links, diff and whitespace. No secrets, private keys, process environments or application data collected. Section 4 remains unfinished and proposals await human review. No live administrative changes, commit or push.

## Section 3 closed on human OCI evidence — recorded 2026-09-08 — Human accepted

Source: Marijus's final human-supplied OCI Console evidence, recorded September 8. Exact Console observation times were not supplied; no independent agent OCI or live verification occurred.

`public-subnet` → Security → Security Lists shows exactly one attached Security List, `Default Security List for demo-vnc`, with pagination `1 - 1 of 1 total items`. No additional Security Lists are attached. Marijus also confirms that earlier human-supplied ingress evidence from this list showed **Stateless: No**, establishing that all three recorded ingress rules are stateful:

| Source | Stateful ingress permission |
|---|---|
| `0.0.0.0/0` | TCP destination port 22 |
| `0.0.0.0/0` | ICMP type 3/code 4 |
| `10.0.0.0/24` | ICMP type 3 |

Together with the earlier no-NSG VNIC evidence and this list's single stateful all-protocol/all-port IPv4 egress rule to `0.0.0.0/0`, this resolves the remaining attachment and statefulness evidence task. The recorded host filtering, human-verified rpcbind retirement, external Mac TCP results, and owner-reconciled UDP 123 live rules support closing the present network/firewall baseline. No other unresolved requirement belongs to Section 3; its completed TODO section is removed without renumbering later sections.

Future Docker forwarding/published-port verification and separately authorized TCP 80/443 opening remain in TODO sections 4 and 6. The gateway's explicit enabled flag, UDP 111/other-source reachability, and fresh saved-rule comparison/reboot persistence remain unverified as previously recorded; these limits do not create additional baseline completion tasks. Recheck relevant state before future rule manipulation or deployment. No universal reachability or runtime/persistent agreement is claimed.

This completion record supersedes earlier Section 3 open-task statements and attachment/ingress-statefulness unknowns below; those dated assessments remain historical evidence. Section 3 is closed **Human accepted**. Marijus accepted the network/firewall baseline and its documentation on 2026-09-08, including the supporting assessment, OCI evidence, rpcbind preflight/retirement, external TCP verification, and UDP 123 reconciliation records below. Their earlier review-status and open-task statements describe historical stages; this acceptance supersedes those statuses without changing the evidence, technical conclusions, or limitations.

Verification: compared the supplied evidence with the recorded topology/rules and remaining roadmap, reviewed the documentation diff, checked relative links and whitespace, and preserved earlier evidence and later TODO sections. No live access or changes, commit, or push.

## UDP 123 live-rule consistency verified by owner — recorded 2026-09-07 — Ready for review

Source: Marijus's fresh human-executed read-only verification on `sokoladas-demo`. The following commands were run consecutively; exact execution times were not supplied:

```bash
sudo nft list chain ip filter InstanceServices | grep -B2 -A2 'dport 123'
sudo iptables-save | grep -E 'InstanceServices.*(dport 123|--dport 123)'
sudo iptables -t filter -S InstanceServices | grep -- '--dport 123'
```

Human-reported excerpts (ellipses denote omitted output):

```text
nft: ip daddr 169.254.169.254 udp dport 123 ... accept
iptables-save: -A InstanceServices -d 169.254.169.254/32 -p udp -m udp --dport 123 ... -j ACCEPT
iptables -S: same destination-restricted rule
```

All three current live representations consistently permit UDP destination port 123 to `169.254.169.254` only. The address and `/32` forms are semantically equivalent. The live-rule discrepancy is resolved on this human evidence and removed from TODO; no firewall modification is implied or required.

Earlier conflicting outputs below remain historical evidence, superseded for current live-rule interpretation. Their cause is not established. These three commands inspect loaded rules; `iptables-save` prints the runtime ruleset and does not itself read or update `/etc/iptables/rules.v4`. No fresh saved-file comparison or reboot-persistence test is claimed. That evidence boundary does not retain the resolved live-representation issue as a Section 3 blocker.

At this September 7 assessment, Section 3 had one remaining evidence item: confirm the complete Security List attachment set for public-subnet and the reported ingress rules' stateful/stateless flags. Earlier statements listing UDP 123 as unresolved describe the assessment at that time and are superseded by this record.

Verification: compared the documentation with the supplied consecutive-command results, retained earlier exact observations, reviewed the diff and relative links/whitespace. No independent agent live verification, live changes, commit, or push. Documentation is Ready for review, not Human accepted.

## External TCP verification and OCI egress — recorded 2026-09-07 — Ready for review

Source: Marijus's human-performed tests from his Mac on 2026-09-07 against public IPv4 `152.70.25.153`, plus human-supplied OCI Console evidence. No independent agent network/OCI verification occurred. Exact test commands, source public IP, and execution times were not supplied.

| External TCP test | Human-reported output | Established result |
|---|---|---|
| 22 | `Connection to 152.70.25.153 port 22 [tcp/ssh] succeeded!` | TCP connection succeeded from this Mac/network at test time |
| 111 | `failed: Operation timed out` | No TCP connection completed within the test timeout |
| 80 | `failed: Operation timed out` | No TCP connection completed within the test timeout |
| 443 | `failed: Operation timed out` | No TCP connection completed within the test timeout |

These are demonstrated source-specific outcomes, consistent with the recorded policy and rpcbind retirement. Timeouts do not locate the filtering layer, prove a particular host/OCI rule caused them, or prove universal unreachability. They do not test UDP 111, IPv6, other sources, or HTTP/TLS behavior. SSH authentication was not part of these reported connection-test outputs; prior SSH authentication evidence remains separate. No additional broad scan is required merely to repeat these scoped TCP results.

`Default Security List for demo-vnc` has **one egress rule**, as reported by Marijus: destination `0.0.0.0/0`, all protocols/all ports, **Stateless: No**. This establishes unrestricted IPv4 outbound permission and statefulness for that Security List's egress rule. It does not override the guest's `InstanceServices` restrictions, establish IPv6 egress, or supply the ingress rules' statefulness. The earlier egress-unknown statements are superseded for this list.

### Historical UDP 123 review — superseded by fresh live verification

The forms in the latest question are semantically equivalent:

```text
nft:           ip daddr 169.254.169.254 udp dport 123 accept
iptables-save: -d 169.254.169.254/32 -p udp --dport 123 -j ACCEPT
```

An IPv4 address and that same address with `/32` match the same single destination. Protocol spelling, counters, and iptables formatting are not a discrepancy.

However, the earlier observations actually supplied were different. The earlier human privileged nft output contained this rule (zero counters shown):

```text
ip daddr 169.254.169.254 udp dport 123  counter packets 0 bytes 0 accept
```

The earlier human `iptables-save` output, timestamped September 7 at 20:14:33 local time, contained this exact line:

```text
-A InstanceServices -p udp -m udp --dport 123 -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j ACCEPT
```

The agent's earlier read of `/etc/iptables/rules.v4` also returned the latter line with **no `-d` destination match**. The OUTPUT jump into this chain was `-A OUTPUT -d 169.254.0.0/16 -j InstanceServices`, so this version permits UDP 123 throughout that link-local destination range; the nft version permits only `169.254.169.254`. Both permit the OCI NTP endpoint and neither opens inbound NTP. The latest conditional example is not a new rule capture or an explicit correction of those earlier observations.

The genuine evidence conflict therefore remains the **absent destination match**, not `/32` serialization. No cause or live defect is established. Resolve it by a same-session read-only capture of nft/iptables-save and the saved IPv4 file, or a human correction identifying which earlier pasted observation was inaccurate. No rule change is justified from this record. It does not block retaining the present firewall policy; it prevents claiming a fully reconciled runtime/persistent rules inventory or using these snapshots to rewrite/save/restore InstanceServices.

### Section 3 completion review at that time — UDP 123 subsequently resolved

No further live configuration change is currently established as necessary. The host policy direction is selected, rpcbind retirement is human-verified, and the scoped external TCP checks and default-list egress evidence are now recorded. Do not open unused web ports, add UFW, remove packages, or enable IPv6 to complete this section.

Two evidence tasks remain before claiming Section 3's effective-rule inventory fully complete:

- Confirm the complete Security List attachment set for public-subnet and the three reported ingress rules' stateful/stateless flags. No NSGs is already established; egress for the reported list is now established. A separate gateway-enabled screenshot is not a current blocker given the recorded gateway route and successful public IPv4 connection; the exact Console flag remains unrecorded without invalidating the demonstrated path.
- Reconcile the specific UDP 123 destination-match observations above. This is an inventory-evidence task, not a finding that NTP is broken or an instruction to change rules.

Section 3 remains open for those two items. Future TCP 80/443 opening and container forwarding/published-port checks belong to Docker/web deployment and have been moved to TODO sections 4 and 6; they need not hold the present baseline assessment open. UDP 111 and other-source reachability remain explicitly untested, but absence of all-network testing is not by itself a new blocker after the human-verified listener removal. Human acceptance remains separate from Ready for review.

Verification: compared new evidence with the human report and earlier exact rule outputs, reviewed the documentation/task diff, checked relative links and whitespace, and preserved historical entries. No live access or changes, commit, or push.

## Human-executed rpcbind retirement — recorded 2026-09-07 — Ready for review

Source: Marijus reports the human-approved change was executed successfully on `sokoladas-demo`. Exact execution and verification times were not supplied. No independent agent live verification was performed for this documentation update.

Human-executed commands:

```bash
sudo systemctl disable --now rpcbind.socket rpcbind.service
sudo systemctl mask rpcbind.socket rpcbind.service
```

| Human verification | Reported result |
|---|---|
| `rpcbind.socket` | Masked, inactive (dead) |
| `rpcbind.service` | Masked, inactive (dead) |
| `sudo ss -lntup \| grep ':111'` | No output; no port-111 listener reported by this check |
| `sudo rpcinfo -p` | `can't contact portmapper: RPC: Remote system error - Connection refused` |
| Packages | Not removed; rpcbind and nfs-common retained |

The refused local portmapper query is the expected result of this retirement, corroborating the inactive units and absent port-111 listener. It is not an external reachability test. Both the daemon and activation socket were masked to prevent reactivation; package dependencies remain installed.

This later human evidence supersedes earlier enabled/running/listening observations and the pending retirement proposal for current recorded state. Earlier assessments remain historical evidence. The rollback commands and success checks in the preflight below remain available if restoration is separately authorized; rollback was not performed or tested. No post-reboot test, broader service-health check, or fresh firewall comparison was supplied, and none is claimed.

The rpcbind retirement item is implemented and verified on the supplied human evidence and removed from TODO. Section 3 remains open for OCI rule details, the preserved outbound UDP 123 discrepancy, external exposure verification, and future Docker/web enforcement. This documentation is Ready for review, not Human accepted. No agent SSH/OCI access, additional live changes, commit, or push occurred.

## rpcbind dependency preflight — 2026-09-07 — Ready for review

**Conclusion: safe to disable/mask** `rpcbind.service` and `rpcbind.socket` for the currently observed local web/application/database host role, retaining installed packages. This is a scoped operational assessment, not proof that arbitrary future RPC workloads will work, permission to execute, or a package-removal assessment. No service was stopped, disabled, masked, removed, or reconfigured.

Source: authorized read-only SSH as marijus at `152.70.25.153`, hostname `sokoladas-demo`, starting 17:40:18 UTC on September 7; a subsequent batch was timestamped 17:41:11–17:41:12 UTC, followed by the configuration/state-count checks described below. No OCI access occurred. The findings support the earlier conditional retirement proposal; Section 3 remains open for the owner's disposition and separately authorized implementation/verification.

### Service and installed-package dependencies

- Both rpcbind units report `UnitFileState=enabled`, `ActiveState=active`, `SubState=running`. TCP/UDP 111 remains bound on wildcard IPv4/IPv6; `/run/rpcbind.sock` is listening. `rpcbind.service` requires `rpcbind.socket` and wants `remote-fs-pre.target` and `rpcbind.target`.
- A scan of **installed** dpkg Pre-Depends, Depends, Recommends, and Suggests fields found exactly one package relation mentioning rpcbind: `nfs-common` **Depends** on it. No installed package recommendation for rpcbind was found. `apt-cache rdepends --installed rpcbind` corroborated nfs-common. Package presence requirements do not require the daemon to remain running; retaining both packages preserves that package dependency.
- Loaded reverse dependencies show rpcbind.service under multi-user.target and rpcbind.socket under rpcbind.service/sockets.target. Scanning installed unit files additionally found inactive `rpc-statd.service` with `Requires=rpcbind.socket`: loaded-only dependency output was incomplete for dormant units. rpc-statd identifies itself as the NFSv2/v3 locking status monitor.
- `nfs-common` and rpcbind remain installed. `autofs` and `ypbind-mt` have no package records; `nis` and `libnss-nis` are not installed. `autofs.service` and `ypbind.service` are not found.

### Mounts, automounts, and RPC consumers

- `findmnt` returned no NFS/NFS4 data mounts. The root filesystem is ext4 on `/dev/sda1`; fstab contains only ext4, vfat, and swap entries. Installed and loaded mount/automount listings contain no configured NFS data mount. `proc-fs-nfsd.mount` is an installed static support unit, not an observed mounted NFS export; `/run/rpc_pipefs` is active support infrastructure, not a remote data mount.
- The only loaded automount is systemd's `proc-sys-fs-binfmt_misc.automount`, unrelated to NFS. `/etc/auto.master`, `/etc/auto.master.d`, `/etc/autofs.conf`, and `/etc/default/autofs` are absent; no `/etc/auto.*` maps were returned. `/etc/exports` and `/etc/exports.d` are absent.
- No active RPC/NFS reference outside the packaged NFS/rpcbind units appeared in the inspected local, runtime, generated, and vendor systemd unit files or system cron directories/crontab. Symlink files were skipped by the text scan; installed/loaded unit listings were checked separately. This was not a scan of every executable on disk.
- `nfs-client.target` is active. `rpc-statd-notify` is active/exited; rpc-statd, rpc-gssd, rpc-svcgssd, and nfs-idmapd are inactive. Local `rpcinfo -p 127.0.0.1` returned only portmapper program 100000, versions 2/3/4 over TCP/UDP. No other registered RPC server or recognizable active NFS/NIS userspace consumer appeared in the inspected process names. An unregistered/transient RPC client is not excluded solely by rpcinfo.
- `/var/lib/nfs/sm` and `sm.bak` are readable and both have zero entries: no recorded statd peer files there. `/proc/fs/nfsfs/servers` and `volumes` are absent; failed reads were not treated as successful empty tables.
- `/etc/nfs.conf` contains section headers plus `pipefs-directory=/run/rpc_pipefs` and `manage-gids=y`; `/etc/idmapd.conf` contains verbosity and nobody/nogroup mappings. No mount/server selection was found in these files; `/etc/nfsmount.conf` is absent and no matching configuration drop-in files were returned.
- `/etc/nsswitch.conf` contains `netgroup: nis`, but no automount entry or other NIS match appeared. With no installed NIS NSS module/ypbind package, no ypbind service, and no observed consumer, this line does not establish working NIS use or a rpcbind requirement.
- `/usr/local/bin`, `/usr/local/sbin`, `/opt`, and `/srv` each contain zero entries. These scoped negatives support the existing fresh-host context, not a claim that all protected or user-specific configuration was audited.

### OCI/Ubuntu tooling and expected operational impact

No direct rpcbind dependency/recommendation appeared in the installed cloud-init, Ubuntu metapackage, open-iscsi, or multipath-tools metadata. Oracle Cloud Agent and updater systemd dependencies refer to their snap mount, ordinary system targets, and networking, not rpcbind. The agent's readable snap metadata contains no rpcbind/nfs-common/mount.nfs reference. iscsid and multipathd dependencies do not name rpcbind. The cloud-init package family was covered by package metadata and the unit-file scan; an empty response for the legacy `cloud-init.service` name was not treated as evidence of a loaded service. No complete audit of compiled agent plugins was performed.

The evidence supports no expected loss to the currently observed SSH, local storage, DNS/DHCP, time synchronization, or guest-agent role from retiring rpcbind alone. This is an inference from dependencies and observed use, not a stop/restart experiment. Original image installation provenance remains unproven and does not need to be known to make this scoped runtime decision.

What would be lost: local/remote rpcbind registration and lookup on TCP/UDP 111 and its Unix socket; dependent legacy NFSv2/v3 status/locking services such as rpc-statd would be unable to start while the socket is masked. Future legacy NFS or another application requiring local portmapper would need this decision reversed. This does not disable every kind of RPC transport. Ubuntu's [nfs.systemd manual](https://manpages.ubuntu.com/manpages/resolute/man7/nfs.systemd.7.html) states that NFSv4-only operation does not require rpcbind, whereas dependent NFSv3 services will refuse to start when it is masked. No NFSv4 deployment was tested here.

### Exact rollback for the proposed service/socket retirement

Only if the separately approved change later disables/masks these two units while retaining packages, restore the observed enabled/running state with:

```bash
sudo systemctl unmask rpcbind.socket rpcbind.service
sudo systemctl enable rpcbind.socket rpcbind.service
sudo systemctl start rpcbind.socket
sudo systemctl start rpcbind.service
systemctl show rpcbind.socket rpcbind.service -p Id -p UnitFileState -p ActiveState -p SubState
sudo ss -lntup
rpcinfo -p 127.0.0.1
systemctl --failed --no-pager
```

Success: both units enabled and active/running, IPv4/IPv6 TCP/UDP 111 restored, local portmapper registration returned, and no new relevant failed units. If retirement caused a dependent consumer to fail, restore rpcbind first and separately restart/verify that identified consumer as appropriate; none currently runs that requires such restoration. Do not blindly reset failure state. No package install, firewall restore, reboot, or OCI action is part of this rollback. Commands are proposed and unexecuted; rollback has not been experimentally tested. Existing marijus SSH, ubuntu fallback, and human-tested Serial Console remain the recorded access/recovery paths.

### Verification limits

`sudo -n true` still required interactive authentication; no elevated observation was available in the agent session. The service/package/configuration/state evidence used for this conclusion was readable without sudo. Other users' protected crontabs, home/root scripts, other process mount namespaces, and private agent configuration were not exhaustively inspected. These residual limits do not reveal a concrete dependency and do not outweigh the directly observed empty NFS configuration/use and standard dependencies for this narrow, reversible service-only recommendation. They do prevent a universal no-consumer guarantee or package-removal clearance.

The preflight establishes the evidence supporting a future decision; no behavior with rpcbind stopped is claimed. The earlier UDP 123 discrepancy and OCI/external verification tasks are unchanged and unrelated to this dependency result. Reviewed the documentation diff, attribution, relative links, and whitespace. No secrets or process environments collected, no live administrative changes, commit, or push; normal read-session logging/access-time effects were not suppressed.

## OCI network evidence and firewall decisions — 2026-09-07 — Ready for review

Source: Marijus's OCI Console observations dated 2026-09-07, combined with the separately attributed guest assessment below. No independent OCI verification or new SSH inspection was performed for this update. Human policy directions are recorded as directions, not authorization to execute changes or acceptance of this documentation. This later record supersedes the earlier assessment's open policy questions and OCI unknowns only where evidence below resolves them.

### 1. Final observed network topology

| Object | Human-supplied Console evidence |
|---|---|
| Primary VNIC of `sokoladas-demo` | Subnet `public-subnet`; private IPv4 `10.0.0.52`; public IPv4 `152.70.25.153`, **Ephemeral**; route table `Default Route Table for demo-vnc`; **no NSGs** |
| `public-subnet` | `10.0.0.0/26`, Public (Regional); no Oracle-allocated, BYOIP, or ULA IPv6 prefix |
| `Default Route Table for demo-vnc` | Static `0.0.0.0/0` route to Internet Gateway `demo-internet-gateway`, description `Internet access` |
| `Default Security List for demo-vnc` ingress | `0.0.0.0/0` to TCP destination 22; `0.0.0.0/0` to ICMP type 3/code 4; `10.0.0.0/24` to ICMP type 3. No TCP/UDP 111 or TCP 80/443 ingress rule observed |

Combined topology: recorded public IPv4 → primary VNIC private IPv4 `10.0.0.52` in `public-subnet`; guest `enp0s6` has `10.0.0.52/26`, default gateway `10.0.0.1`; the associated route table points Internet traffic at `demo-internet-gateway`. The public address is ephemeral, not reserved or guaranteed stable. Guest IPv6 remains enabled with only `fe80::17ff:fe03:2073/64` on enp0s6, loopback `::1`, and no IPv6 default route; the subnet has no IPv6 prefix.

The supplied report identifies the relevant default Security List but does not explicitly enumerate the subnet's complete Security List attachment set, egress rules, or stateful/stateless flags. These details and the gateway's explicit enabled status were not supplied. Do not infer them from defaults or object names. The VCN-wide CIDR remains historical evidence; the ICMP source CIDR alone does not reverify it.

### 2. Effective current exposure by service/port

This table separates observed filtering from end-to-end reachability. OCI permission refers to the reported Security List, not an independently audited union of all attachments.

| Service/port | Guest listener | Loaded host filter | Reported OCI ingress | Demonstrated external reachability |
|---|---|---|---|---|
| SSH TCP 22 | Wildcard IPv4/IPv6, sshd/systemd | IPv4 NEW TCP 22 accepted; IPv6 ACCEPT | IPv4 permitted from `0.0.0.0/0` | Successful prior SSH from inspection source only |
| rpcbind TCP/UDP 111 | Wildcard IPv4/IPv6, rpcbind/systemd | Ordinary new non-loopback IPv4 input rejected; IPv6 ACCEPT | No allow observed | Not tested; no public exposure demonstrated |
| HTTP TCP 80 / HTTPS TCP 443 | None | Ordinary new IPv4 input rejected; IPv6 ACCEPT | No allow observed | Not tested; no service demonstrated |
| DNS TCP/UDP 53 | `127.0.0.53`, `127.0.0.54`, systemd-resolved | Loopback accepted | No allow in supplied list | No externally bound DNS socket observed |
| DHCP UDP 68 | `10.0.0.52%enp0s6`, systemd-networkd | No explicit INPUT port-68 allow; do not equate this with DHCP failure | No allow in supplied list | Guest DHCP lease observed; not a public application endpoint |
| chrony UDP 323 | `127.0.0.1`, `::1`, chronyd | Loopback accepted | No allow in supplied list | No externally bound chrony control socket observed |
| Application/database ports | None identified in assessed namespace | Remaining ordinary new IPv4 input rejected | No allow in supplied list | Not demonstrated; reassess with containers |

Host IPv4 also accepts RELATED/ESTABLISHED traffic and ICMP before its final reject. The OCI list is more selective about ICMP: the two types/sources above. IPv6 ACCEPT is a real guest filtering property, but neither global IPv6 addressing nor an IPv6 Internet route is present in the evidence. No claim that IPv6 is disabled or that link-local peers are filtered is made. The earlier nft dump showed no NAT/Docker tables; future published ports require fresh checks.

### 3. Target firewall policy — owner direction

Retain Oracle-image `iptables-nft` with `netfilter-persistent`; do not install UFW simply to add another abstraction. Preserve `InstanceServices` unchanged unless a specific justified change is separately approved. Keep administrative TCP 22 available, including the currently reported OCI source `0.0.0.0/0`. Do not impose one fixed administrator source IP: administration uses changing networks, SSH is key-only by the recorded human hardening evidence, and Serial Console recovery is human-verified.

Do not enable OCI IPv6 now. Retain and document the guest's current permissive IPv6 state; any future global IPv6 enablement requires an explicit IPv6 host-firewall and OCI security-rule design first. No guest IPv6 kernel or firewall change is proposed now.

Future public application ingress is **TCP 80 and TCP 443 only**, in addition to TCP 22; UDP 443 is not included. Keep web ports closed until the separately approved HTTP/reverse-proxy deployment needs them. Section 3 does not require opening unused ports. Keep TCP/UDP 111 and direct application/database ports outside intended public exposure. Preserve current provider access and ICMP behavior; no new egress policy is selected from incomplete OCI egress evidence. Docker forwarding/published-port policy must be reviewed during Docker/web deployment rather than assuming today's INPUT chain will govern it.

### 4. Recommendation for nfs-common / rpcbind

No demonstrated workload requires network RPC: no NFS mounts, only portmapper registered, and the intended local web/application/database role has no stated NFS dependency. The installed `nfs-common` dependency explains why rpcbind can be present, but not its original installation provenance. OCI image membership alone does not prove a runtime requirement. Conversely, the current evidence is not a complete dependency/removal audit.

Recommend retaining the packages initially and, after a short dependency preflight and separate approval, stopping, disabling, and masking **both** `rpcbind.service` and `rpcbind.socket`. Disabling only the service is insufficient to prevent socket activation. Ubuntu's [NFS systemd manual for the installed nfs-common version](https://manpages.ubuntu.com/manpages/resolute/man7/nfs.systemd.7.html) documents masking rpcbind when NFSv2/v3 is not required. This is a reasonable reversible reduction of an unused listener, not an urgent repair of demonstrated public exposure.

Before execution, confirm no configured dormant NFS/automount/custom RPC consumer and review reverse dependencies for both units and both packages. Do not assume iscsid/multipathd or the Oracle Cloud Agent can be removed with them. Oracle documents separate [link-local metadata, DNS, NTP, and iSCSI services](https://docs.oracle.com/en-us/iaas/Content/Security/Reference/compute_security.htm); that documentation does not certify this VM's full dependency graph.

Removing `nfs-common` and `rpcbind` is also reasonable in principle if NFS is deliberately excluded, but defer package removal until an observational `apt-get -s remove nfs-common rpcbind` plan and installed reverse dependencies have been reviewed. Do not use autoremove or purge as a shortcut. Package retention with masked units avoids an unreviewed package cascade and is easier to reverse. NFSv2/v3 or another RPC consumer introduced later would require revisiting the decision.

### 5. Remaining issues and Section 3 completion boundary

**UDP 123 discrepancy retained:** supplied nft output allows UDP 123 only to `169.254.169.254`; supplied iptables-save and the readable saved file allow UDP 123 to the range selected by the OUTPUT jump (`169.254.0.0/16`). Both allow OCI's documented NTP address `169.254.169.254:123`, and neither opens inbound public NTP. Thus this discrepancy does **not** prevent adopting the retain-existing-policy direction, leaving web ports closed, or evaluating rpcbind retirement. It does prevent claiming exact runtime/persistent agreement or safely regenerating/replacing `InstanceServices` from these inconsistent snapshots. No cause (transcription, timing, or translation) has been proven.

A same-session read-only recapture of `sudo nft list ruleset`, `sudo iptables-save`, and the saved IPv4 file should reconcile the NTP rule before a rule rewrite/save/restore is proposed. Inspect the exact rule rather than assuming equal rendering. No rule correction is justified yet. This qualifies the earlier assessment's broader statement that the discrepancy had to be resolved before any policy decision.

Section 3 remains open for the human rpcbind disposition decision and, if adopted, its separately authorized implementation/verification; remaining effective-rule evidence (complete subnet Security List attachments, egress and statefulness) and scoped external exposure verification are also unfinished. These are limits to a claim of completed effective-exposure verification, not reasons to install a firewall or open ports. The NTP reconciliation remains an evidence follow-up and a prerequisite specifically to manipulating the affected rules. Web/container enforcement is deferred to deployment; absence of a web service is not an immediate remediation requirement.

### 6. Exact proposed live changes — not authorized or executed

**No host-firewall, OCI, SSH, DNS, IPv6, or package change is proposed for immediate execution.** The concrete optional service-retirement proposal for separate approval targets only rpcbind on `sokoladas-demo`, subject to the dependency preflight above:

```bash
sudo systemctl disable --now rpcbind.socket rpcbind.service
sudo systemctl mask rpcbind.socket rpcbind.service
```

Verify both units inactive and masked, no TCP/UDP 111 listener in privileged `ss -lntup`, no new relevant failed units, unchanged firewall rules, and continued SSH/provider-service health. Capture pre-change status first. Existing evidence records both units enabled/active; rollback to that state, if needed, is:

```bash
sudo systemctl unmask rpcbind.socket rpcbind.service
sudo systemctl enable --now rpcbind.socket rpcbind.service
```

These commands are review material, not a tested runbook or permission to execute. The recorded primary access is marijus SSH, fallback is ubuntu SSH with sudo, and independent recovery is the owner's tested Serial Console path. Fresh prerequisites and success checks belong with any authorized live execution.

Future web deployment would separately propose TCP 80/443 ingress in the applicable OCI rule set and the host/container forwarding path, with listener and external verification. Exact deployment rules depend on the chosen container topology and are not proposed for execution now.

Documentation verification: compared every Console field with the human report, cross-checked host/listener claims against the earlier evidence, retained the NTP discrepancy and provenance limits, reviewed the diff and relative links/whitespace. Public vendor documentation was consulted for technical context only; no authenticated OCI access, SSH session, live change, commit, or push occurred in this update.

## Network and firewall assessment — 2026-09-07 — Ready for review

Authorized read-only SSH inspection of `marijus@152.70.25.153`, reporting `sokoladas-demo`, at 17:11:55–17:13:07 UTC (remote clock). No live configuration, package, service, firewall, kernel, OCI, or DNS changes were made. The assessment and documentation are Ready for review with the human-supplied privileged evidence below; effective public exposure and TODO section 3 are not complete.

### 1. Observed guest network state

- `lo` is administratively up, with `127.0.0.1/8` and `::1/128`. `enp0s6` is UP/LOWER_UP, uses `virtio_net`, MTU 9000, and has `10.0.0.52/26` plus link-local `fe80::17ff:fe03:2073/64`. These were the only interfaces returned by `ip -br link/address`; no Docker bridge appeared.
- IPv4 main routes: default via `10.0.0.1` on `enp0s6`, DHCP source `10.0.0.52`, metric 100; connected `10.0.0.0/26`; explicit on-link routes to `10.0.0.1`, `169.254.0.0/16`, and `169.254.169.254`. Local-table routes cover the guest/loopback addresses and broadcasts.
- `networkctl status enp0s6` reports routable/configured, DHCPv4 via `169.254.169.254`, gateway `10.0.0.1`, DNS `169.254.169.254`, and search domain `demovnc.oraclevcn.com`. This does not verify the recorded OCI VCN name or control-plane routes.
- IPv6 routes cover link-local `fe80::/64`, the local addresses, and multicast `ff00::/8`; no global IPv6 address or IPv6 default route was returned. IPv4 rules are the standard local/main/default table lookups; IPv6 rules are local/main lookups.
- IPv4 is operational. IPv6 `disable_ipv6` values for `all`, `default`, and `enp0s6` are all `0`: IPv6 is enabled, despite lacking observed global connectivity. IPv4 `ip_forward` and IPv6 `all/forwarding` are `0`.
- The successful key-authenticated SSH session to `152.70.25.153:22` establishes reachability from this inspection source at that time. The public address is not assigned to a guest interface in the returned address list. No general outbound Internet test or external port scan was performed.

### 2. Observed host firewall state

| Mechanism | Observed evidence |
|---|---|
| UFW | Package not installed (`un`); `ufw.service` not found. An existing `/etc/ufw` directory from earlier inspection does not establish UFW enforcement |
| iptables | `iptables` 1.8.11-2ubuntu3 installed; both `iptables --version` and `ip6tables --version` report `nf_tables` backend |
| nftables | Package 1.1.6-1 installed; `nftables.service` disabled and inactive. This does not mean the kernel nftables ruleset is empty |
| Persistence | `iptables-persistent` and `netfilter-persistent` 1.0.24 installed; `netfilter-persistent.service` enabled, active/exited, startup status 0. Its installed plugins load `/etc/iptables/rules.v4` and `rules.v6` using the restore tools. Plugins were read, never executed by the assessment |
| Loaded rules | Agent queries were denied without interactive sudo. Marijus subsequently supplied privileged `nft list ruleset`, `iptables-save`, and `ip6tables-save` output on September 7; save timestamps are 20:14:33 and 20:14:49 server local time (17:14:33/49 UTC). The outputs establish loaded IPv4/IPv6 filter rules; attribution is human-supplied evidence, not agent sudo execution |

Both readable saved rule files contain `CLOUD_IMG` provenance comments identifying the Cloud Image build process and Oracle Cloud Infrastructure configuration. Their displayed modification date is August 14; this is file metadata, not proof of the original installation history or currently loaded state.

Saved IPv4 filter table, in order:

```text
INPUT policy ACCEPT
  ACCEPT RELATED,ESTABLISHED
  ACCEPT ICMP
  ACCEPT input on lo
  ACCEPT NEW TCP destination port 22
  REJECT all remaining input with icmp-host-prohibited
FORWARD policy ACCEPT
  REJECT all forwarded traffic with icmp-host-prohibited
OUTPUT policy ACCEPT
  jump to InstanceServices for destination 169.254.0.0/16
```

The saved `InstanceServices` chain permits TCP 3260 for UID 0 to `169.254.0.2/32`, `169.254.2.0/24`, `169.254.4.0/24`, and `169.254.5.0/24`; TCP 80 to `169.254.0.2`, `169.254.0.4`, and `169.254.169.254`; UID-0 TCP 80 to `169.254.0.3`; TCP/UDP 53 and UDP 67/69 to `169.254.169.254`; and UDP 123 within the link-local destination range selected by the OUTPUT jump. It then rejects remaining TCP there with TCP reset and remaining UDP with ICMP port-unreachable. These rules are relevant to preserving provider-service access in a future policy.

Saved IPv6 contains only a filter table with INPUT, FORWARD, and OUTPUT policies ACCEPT, with no appended rules. The saved IPv4 policy would reject new non-loopback inbound TCP/UDP 111 and TCP 80/443 if loaded unchanged; the saved IPv6 policy would not filter them. The subsequent human-supplied loaded rules confirm this INPUT/FORWARD behavior and the empty IPv6 ACCEPT chains. The nft dump contains only `ip filter` and `ip6 filter`, with no NAT or Docker tables shown. Both save outputs match the saved rule structure apart from counters. A discrepancy remains: the supplied nft output scopes the UDP 123 exception to `169.254.169.254`, whereas saved rules and iptables-save leave its destination unrestricted within the OUTPUT jump to `169.254.0.0/16`. Do not claim exact agreement for that exception; a same-session recapture is needed to reconcile it. Counter values and two rejected IPv4 packets do not identify which public ports or sources were tested.

### 3. Services/listeners and their apparent necessity

Complete TCP listening and UDP bound/unconnected socket inventory returned by `ss -lntup` in the session's network namespace:

| Protocol | Local address(es) | Port | Attribution and purpose |
|---|---|---|---|
| TCP | `0.0.0.0`, `[::]` | 22 | `ssh.socket`/`ssh.service`; systemd socket listing confirms ownership; required for the recorded administrative path |
| TCP and UDP | `0.0.0.0`, `[::]` | 111 | `rpcbind.socket`/`rpcbind.service`; socket unit explicitly binds these four endpoints |
| TCP and UDP | `127.0.0.53%lo`, `127.0.0.54` | 53 | `systemd-resolve` PID 607 in owner’s privileged output; loopback DNS |
| UDP | `10.0.0.52%enp0s6` | 68 | `systemd-network` PID 1111 in owner’s privileged output; DHCPv4 client |
| UDP | `127.0.0.1`, `[::1]` | 323 | `chronyd` PID 1285 in owner’s privileged output; loopback control |

Unprivileged `ss` returned no process details. Marijus’s subsequent privileged `ss -lntup` confirms the same complete socket list and all process attributions: sshd PID 1244 plus systemd PID 1 for port 22; rpcbind PID 901 plus systemd PID 1 for port 111; other PIDs are in the table. No other wildcard TCP/UDP listener appeared. No listener appeared on 80, 443, 2049, or a recognizable application/database port. This does not enumerate other network namespaces or prove the absence of NAT-only published ports.

`rpcbind` package 1.2.7-1build2 owns `/usr/sbin/rpcbind` and its socket unit. Both service and socket are enabled and active/running; the process runs as `_rpc` (PID 901). Configuration supplies `OPTIONS="-w"`; the socket unit explicitly binds wildcard IPv4/IPv6 TCP/UDP 111. The unit requires its socket, so any later service-retirement proposal must account for socket activation as well as the daemon.

Installed `nfs-common` 1:2.8.5-1ubuntu1 depends on rpcbind and is its only installed reverse dependency returned by `apt-cache rdepends --installed rpcbind`. `nfs-common` is marked manually installed by APT; this flag does not identify a human installation. Image-supplied NFS client support is a plausible explanation for rpcbind's presence, not a proven image-build history. No nfs/rpcbind matches appeared in the inspected current APT/dpkg logs, and `/var/log/installer` was absent. Exact original installation cause remains unknown. Ubuntu documents rpcbind's relationship to NFS services in its [NFS systemd manual](https://manpages.ubuntu.com/manpages/noble/man7/nfs.systemd.7.html); that general relationship is also established by this VM's package metadata.

`nfs-client.target` is enabled/active; `rpc-statd-notify` is active/exited, while `rpc-statd` and `nfs-idmapd` are inactive. `findmnt` found no NFS/NFS4 mounts; `/etc/fstab` had no nfs/rpcbind matches. `/run/rpc_pipefs` exists, which is NFS/RPC support infrastructure, not an NFS data mount. Local `rpcinfo -p 127.0.0.1` returned only portmapper program 100000, versions 2/3/4 over TCP/UDP 111. No NFS server package is installed. Thus there is an installed dependency and active NFS support target, but no observed workload requiring network RPC service. This is insufficient to certify removal as safe for dormant/future mounts or uninspected custom components.

`iscsid`, `multipathd`, and Oracle Cloud Agent services run; no dependency on rpcbind was established for them. No Docker/Podman/Nginx/Apache/Caddy executable was returned by PATH checks, and no corresponding running service appeared. These are scoped negative observations, not a full package/filesystem/container audit.

### 4. Security findings

- Port 111 is an additional wildcard service outside the intended public port set. The observed loaded IPv4 INPUT chain rejects new non-loopback traffic to it unless accepted by the preceding RELATED/ESTABLISHED rule; public reachability remains untested. Local listening alone is not an exposure finding. The current evidence supports reviewing its necessity.
- Loaded and saved IPv4 and IPv6 policies differ materially. Link-local-only IPv6 is not the same as disabled IPv6, and future global addressing would require deliberate IPv6 policy review.
- There is an existing firewall persistence mechanism. UFW absence and an inactive nftables service do not establish an unprotected host. Human-supplied loaded rules now establish the filter state; reconcile the NTP exception discrepancy before defining changes.
- Future HTTP/HTTPS needs a listener and suitable effective host/OCI rules. No web listener is present; the loaded and saved IPv4 rules contain no web ingress allow before rejection. Outbound link-local TCP 80 exceptions do not open inbound HTTP.
- Future container exposure needs separate published-port/NAT/forwarding verification; current socket output alone cannot prove privacy. No firewall weakening or service retirement has been authorized.

### 5. Unknowns requiring OCI-side or external verification

Record the actual VNIC/subnet attachments, all associated Security Lists and NSGs, their combined ingress/egress rules (including sources and stateful/stateless behavior), effective route table, Internet gateway state, public-IP mapping/allocation, and IPv6 assignments. Guest routes do not verify these control-plane objects or the historical VCN/subnet/gateway names.

External verification from agreed sources is needed for TCP 22/80/443 and TCP/UDP 111, plus relevant IPv6 and private-service reachability after policy decisions. SSH success proves only this tested source/session. No DNS, arbitrary-source reachability, cloud firewall, or external UDP behavior was tested.

Marijus supplied the requested privileged socket/rule outputs, resolving the initial authentication-related evidence gap. UFW also returned command not found under sudo. Remaining guest follow-up is a same-session read-only recapture of `nft list ruleset` and `iptables-save` to reconcile the UDP 123 destination discrepancy; inspect other backends/namespaces or filtering mechanisms if needed for the eventual exposure verification. These outputs do not audit legacy rules, eBPF filtering, or every network namespace. No alternate-account escalation or authentication bypass was attempted.

### 6. Proposed decisions for human review

These are proposals only; no policy choice is adopted by this assessment.

- Decide whether NFS client capability is required. If not, separately authorize a concrete rpcbind service/socket retirement plan after dependency and recovery review; package removal is a separate decision.
- Decide SSH source restrictions and intended HTTP/HTTPS audience, then choose one reproducible host-firewall management approach informed by the loaded rules and reconciled NTP exception. Preserve required provider-service access and the established recovery path.
- Decide IPv6 exposure before global IPv6 or web deployment; make IPv4/IPv6 policy intentional.
- Obtain OCI-side evidence and reconcile the loaded-rule discrepancy before applying policy; verify exposure again when Docker and the reverse proxy exist.

Evidence method: `ss`, `ip` address/link/routes/rules, `networkctl`, read-only `/proc/sys` values, systemd show/cat/socket/dependency listings, dpkg/APT metadata, `findmnt`, local `rpcinfo`, current package-log keyword searches, and readable saved firewall rules/loader files. Initial local sandbox SSH denial was resolved by an approved network retry; the default key was rejected and the established Oracle key succeeded with strict host-key checking. Remote `rg` was unavailable; the relevant keyword search was repeated with `grep`. Initial agent privileged failures remain recorded; later successful privileged evidence was supplied by Marijus, not independently executed by the agent. Normal SSH/sudo logging and read access-time effects were not suppressed. No secrets, private keys, process environments, or application data contents were captured. No commit or push.

## OCI Serial Console recovery — verified 2026-09-07 — Ready for review

Source: Marijus's human-performed end-to-end verification on 2026-09-07. A local OCI console connection was created using a dedicated RSA key, the serial console was reached successfully, and interactive login as `marijus` using the local Linux password succeeded.

This establishes a tested recovery access path independent of normal SSH access. Recovery uses the OCI console connection and its dedicated key to reach the serial console, followed by the local Linux account/password for login; it does not require enabling password authentication in sshd. No key material or password is recorded here.

The report establishes the successful access sequence, not a tested repair of every possible boot, OS, or network failure. Exact console connection commands/identifier and credential custody details were not supplied. This documentation update involved no agent server/OCI access or changes.

The final recovery-access item is complete on this human evidence, so TODO section 2 has no remaining items and is removed. This new documentation entry is Ready for review; earlier accepted hardening remains Human accepted.

## Human-performed SSH hardening — recorded 2026-09-07 — Human accepted

Source: Marijus's report of completed hardening and verification. No additional agent live inspection or changes were performed. Exact execution times were not supplied. This later report supersedes the earlier assessment's unresolved authentication/fallback findings where explicitly verified below; the original assessment remains historical evidence.

Human-created `/etc/ssh/sshd_config.d/90-sokoladas-hardening.conf`:

```text
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
X11Forwarding no
AllowTcpForwarding yes
```

Before activation, the owner ran `sudo /usr/sbin/sshd -t` successfully (exit 0) and reports that `sudo /usr/sbin/sshd -T` confirmed all six intended effective values. The SSH service was then reloaded. These effective-value checks are the supplied evidence that fragment precedence produced the intended settings; do not infer precedence from the filename alone.

### Human verification and decisions

- Before hardening, ubuntu key-based SSH login and passwordless sudo were tested successfully. Root and opc key logins executed their cloud-image forced commands directing login as ubuntu; neither provided a shell.
- The owner inspected `/root/.ssh/authorized_keys` and `/home/opc/.ssh/authorized_keys` and reports restrictive forced-command entries disabling port, agent, and X11 forwarding. Exact entries and permissions were not supplied; no key material is recorded here.
- After reload, new marijus and ubuntu key-based sessions both succeeded, ubuntu retained working passwordless sudo, and direct root SSH login was rejected.
- Marijus is the primary administrator. Ubuntu is retained as the tested recovery administrative account. Opc is retained with no cleanup currently required; its redirect test was before hardening, not a claimed post-reload test.
- Direct root SSH, password authentication, and keyboard-interactive authentication are prohibited; public-key authentication remains enabled. X11 forwarding is disabled. TCP forwarding remains enabled intentionally for legitimate administrative SSH tunneling. SSH remains on port 22.

### Remaining limits and recovery boundary

The tested ubuntu path provides an alternative administrative account over SSH, not evidence of recovery when SSH or networking is unavailable. Subsequent human verification on 2026-09-07 established OCI Serial Console login as marijus, independent of normal SSH, as recorded above. The owner subsequently executed `sudo -l -U marijus`, which reported `(ALL : ALL) ALL`, establishing marijus sudo entitlement to run any command as any user/group. No account-specific `sshd -T -C` results, post-reload negative password/keyboard-interactive tests, forwarding exercise, firewall checks, or OCI checks were supplied. Do not infer them from the reported effective settings and successful key sessions.

The hardening implementation, effective-value review, and fresh-session tests are recorded as completed human work. The documentation is Human accepted; the subsequent Serial Console verification recorded above closes the final section 2 recovery task. No broader authorization is implied.

## SSH/access assessment — 2026-09-07 — Ready for review

Read-only SSH inspection as `marijus` at `152.70.25.153`, hostname `sokoladas-demo`; remote timestamps 14:12:21–14:13:08 UTC. No hardening was implemented. The following distinguishes observed files/protocol behavior from unverified effective policy.

### Observed current state

| Area | Evidence and result |
|---|---|
| Key login | Client restricted to public-key authentication with the explicit Oracle Ed25519 key, password/keyboard-interactive disabled, strict host-key checking and host-key updates disabled. Verbose SSH reported `Authentications that can continue: publickey` and successful authentication using `publickey`. This establishes this account/source/session, not every account or connection context |
| Readable SSH configuration | `/etc/ssh/sshd_config` includes `/etc/ssh/sshd_config.d/*.conf`. The directory contained only `60-cloudimg-settings.conf`, with `PasswordAuthentication no`. Both files are root-owned, mode 644; fragment directory mode 755 |
| Other explicit settings | Main file sets `KbdInteractiveAuthentication no`, `UsePAM yes`, `X11Forwarding yes`, `PrintMotd no`, `AcceptEnv LANG LC_* COLORTERM NO_COLOR`, and the SFTP subsystem |
| Root/public-key policy and restrictions | `PermitRootLogin prohibit-password`, `PubkeyAuthentication yes`, and `AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2` occur only as comments. No active Match, AllowUsers, AllowGroups, DenyUsers, or DenyGroups directives appeared in the inspected main file/fragment. Commented defaults are not an effective-policy result |
| Effective configuration limitation | Unprivileged `/usr/sbin/sshd -T` failed: `no hostkeys available -- exiting`. This does not mean the running daemon lacks host keys; the successful handshake proves it has a usable key. No privileged retry was made |
| Listener/service state | `ssh.service` and `ssh.socket` active/running; socket listens at `0.0.0.0:22` and `[::]:22`, corroborated by `ss -lnt`. No unit drop-ins reported. Service starts `/usr/sbin/sshd -D $SSHD_OPTS`; readable `/etc/default/ssh` has empty `SSHD_OPTS` |
| marijus | UID 1002, `/home/marijus`, `/bin/bash`; groups marijus/sudo/users. `passwd -S marijus` reports `P` (password set); no password or hash collected. `sudo -n -l` denied with interactive authentication required; actual authorized sudo commands remain unknown |
| ubuntu | UID 1001, `/home/ubuntu`, `/bin/bash`; groups ubuntu/adm/cdrom/sudo/dip/lxd. Cloud configuration names ubuntu as default user, with `lock_passwd: True` and intended `ALL=(ALL) NOPASSWD:ALL`. These are provisioning settings, not verified current password/sudo state or a tested fallback login |
| opc | UID 1000, `/home/opc`, `/bin/sh`, only opc group; no processes returned by `ps -u opc -o user,comm`. `/etc/cloud/cloud.cfg.d/99-oracle-compute-user-redirect.cfg` declares default user plus `opc` with `ssh_redirect_user: true`, and identifies itself as cloud-image-build generated/modified. This supports an intended Oracle-image redirect account toward the default ubuntu user; actual authorized-key redirect behavior is unverified |
| Other accounts | root has UID 0 and `/bin/bash`; `ocarun` is described as Oracle Cloud Agent Runcommand Service User with `/usr/sbin/nologin`. No additional UID-0 account appeared in `getent passwd`. No sudo entitlement is inferred merely from a shell or account name |
| Key metadata | marijus home 750, `.ssh` 700, `authorized_keys` 600, all owned by marijus; authorized_keys readable, contents not collected. SSH debug identifies `/home/marijus/.ssh/authorized_keys:1` as the accepted key location, with agent-forwarding/port-forwarding/pty/user-rc/x11-forwarding options. `authorized_keys2` absent. These key options alone do not establish effective forwarding policy |
| Protected metadata | ubuntu/opc homes are each owner-owned mode 750; traversal to their `.ssh`/authorized_keys denied. `/etc/sudoers` root-owned 440; `/etc/sudoers.d` root-owned 750 and listing denied. Root keys and protected account state were not inspected |
| Cloud root intent | `/etc/cloud/cloud.cfg` has `disable_root: true`, with comments describing redirection to the default user. This is not a verified live root-login prohibition |
| File provenance | `dpkg-query -S` found no package owner for the opc redirect fragment, SSH cloud-image fragment, or `/home/opc`; no claim that these paths are currently package-managed |
| Host firewall | Unprivileged `nft list ruleset` and `iptables -S` denied permission. ufw was not found by `command -v`; `/etc/ufw` exists. No conclusion about enabled rules or public exposure; no elevated firewall inspection or OCI inspection performed |

### Findings and access-loss risks

The previously recorded September 6 statement that password SSH had not been disabled does not describe the readable current configuration: the cloud-image fragment disables it and this live marijus session advertised only publickey. The historical report is preserved; when/how that state arose is not established. A local password being set does not prove password-based SSH is possible. No successful password-based SSH access was observed or attempted.

Full effective root policy, authorization-file paths, authentication combinations, and account/source-specific policy remain unverified. The ubuntu account is consistent with the intended fallback administrator, but neither its key login nor current sudo capability was tested. The opc evidence supports a provisioning redirect role, not a proven independent administrator or recovery route.

Potential lockout points include changing/removing the sole tested access path, applying user/group restrictions before confirming fallback access, confusing cloud provisioning intent with current key/sudo state, and changing ports/addresses without accounting for the active SSH socket unit. The readable SSH file explicitly notes lexical fragment ordering and first-value precedence; a later fragment may not override an earlier value. No OCI recovery route has been established by this assessment.

### Unknowns requiring human execution or OCI-side verification

No attempt was made to bypass interactive sudo. Suggested read-only human checks (not executed by the agent):

- `sudo /usr/sbin/sshd -T` for effective parsed defaults, and `sudo /usr/sbin/sshd -T -C user=marijus,addr=<client-ip>,host=<client-hostname>,laddr=10.0.0.52,lport=22` with actual connection values, repeated for ubuntu/opc/root and relevant source contexts. Inspect authentication, root login, authorized-key paths, restrictions, and forwarding settings; parsed disk policy alone does not prove the running daemon loaded the latest files.
- `sudo -l -U marijus`, `sudo -l -U ubuntu`, `sudo -l -U opc`; review sudoers/includes as needed. `sudo passwd -S root`, `sudo passwd -S ubuntu`, and `sudo passwd -S opc` report lock/password status without exposing hashes.
- `sudo stat -c '%a %U:%G %n' /root /root/.ssh /root/.ssh/authorized_keys /home/ubuntu/.ssh /home/ubuntu/.ssh/authorized_keys /home/opc/.ssh /home/opc/.ssh/authorized_keys`; adjust locations after effective-policy checks. Privately inspect key restrictions/forced-command redirection for opc and root; report sanitized conclusions rather than key material.
- `sudo nft list ruleset` and `sudo iptables -S` for host rules; separately verify applicable OCI rules and a usable recovery path. No firewall or recovery capability can be inferred from SSH success alone.

Fallback login usability needs a separately authorized test with the intended credential holder; no ubuntu/opc/root login was attempted. Normal SSH/sudo audit and access-time effects were not suppressed. Permission failures and the failed effective-policy check are recorded limitations, not completed verification. TODO section 2 remains open; hardening decisions require human review.

## Base server setup — recorded 2026-09-07 — Human accepted

Source: Marijus's report of manually completed changes and post-reboot verification. No independent live inspection was performed for this documentation update; exact execution/reboot times were not supplied. This later report supersedes the earlier no-swap observation for intended/current recorded setup without changing that historical evidence.

| Setting / decision | Human-reported state and evidence |
|---|---|
| Hostname | Earlier live inspection observed `sokoladas-demo`; no hostname change is needed for the current task |
| Generated locales | `en_US.UTF-8` and `lt_LT.UTF-8` generated; post-reboot `locale -a` contains `en_US.utf8` and `lt_LT.utf8` |
| System locale | `/etc/default/locale` contains `LANG=en_US.UTF-8`; post-reboot `localectl status` reports the same system locale |
| Timezone / clock | Set to `Europe/Vilnius`; post-reboot `timedatectl` reports that timezone, synchronized clock, and active NTP |
| Swap | Created and enabled a 2 GiB `/swapfile`; after reboot, `swapon --show` reports it and `free -h` reports 2 GiB swap |
| Swap persistence | `/etc/fstab` contains `/swapfile none swap sw 0 0`, confirmed after reboot |
| Swappiness | Owner reports setting `vm.swappiness=10` and persisting it in `/etc/sysctl.d/99-swappiness.conf`; owner confirms post-reboot `sysctl vm.swappiness` returned `vm.swappiness = 10` |
| Host packages | Owner confirms no additional packages are currently required; installation is requirement-driven, not an obligation to install packages now |

### Deliberate interactive-login locale behavior

The owner reports that interactive login still yields `LANG=C.UTF-8` and `LC_CTYPE=C.UTF-8`. Their investigation identified `/etc/profile.d/01-locale-fix.sh`, owned by Ubuntu's `base-files` package, executing `locale-check C.UTF-8`. The deliberate decision is to retain this package-owned behavior. The recorded system default and the login-session environment are distinct; do not treat their difference as unfinished locale work or silently modify the package-owned script.

### Reproduction and verification boundary

The table records the selected locales, timezone, swap size/path, fstab entry, and sysctl persistence location/value needed for future setup. Exact historical creation commands, swapfile permissions/allocation method, and a tested bootstrap script were not supplied; no command sequence is represented as tested automation. Human post-reboot checks establish active swap and the reported locale/timezone state. Swappiness application/persistence is a human change report; the owner additionally confirmed that post-reboot `sysctl vm.swappiness` returned `vm.swappiness = 10`.

TODO section 1 can close: hostname already fits, timezone/locale work is reported verified with an accepted behavioral exception, the swap strategy is selected and active after reboot, and no additional package requirement exists. This does not complete SSH hardening or later roadmap work. Any future automation or independent checks require their own scoped task; no live changes were made by the agent.

## Recorded OCI baseline

| Property | Recorded value |
|---|---|
| Provider / instance | Oracle Cloud Infrastructure / `sokoladas-demo` |
| Home region / instance region | Europe / Frankfurt |
| Architecture / shape | ARM64 (`aarch64`) / `VM.Standard.A1.Flex` |
| CPU / RAM | 2 OCPU / 12 GB |
| OS / kernel family | Ubuntu 26.04 LTS / Oracle Ubuntu ARM64 kernel |
| Boot volume | Approximately 46 GB |
| VCN | `demo-vnc`, `10.0.0.0/24` (name preserved as recorded) |
| Public subnet | `public-subnet`, `10.0.0.0/26` |
| Internet gateway | `demo-internet-gateway` |
| Default route | `0.0.0.0/0` → internet gateway |
| Private IPv4 | `10.0.0.52` |
| Public IPv4 | Previously recorded `152.70.25.153`; dynamically assigned by OCI; observation date unknown |

Do not use the recorded public IP as a guaranteed current endpoint. No reserved/static addressing decision is recorded. DNS naming/addressing choices belong in [README.md](../README.md).

The original README reported that the VM existed and was running, networking and public IPv4 access existed, SSH worked, ARM64 was confirmed using `uname -m`, and Ubuntu 26.04 LTS was confirmed. Captured outputs and observation dates were not included, so these remain historical reports.

Initial provisioning observations (date unknown): approximately 11 GiB RAM available, no swap; `/dev/sda1` approximately 45 GB total, 2.4 GB used, and 42 GB available. These are observations, not resource guarantees or current usage.

## Human-observed OCI cost and allocation verification — 2026-09-07 — Human accepted

Source: Marijus's reported OCI Console observations on 2026-09-07. These are point-in-time human-observed control-plane evidence, recorded without agent access to OCI or the live server. No screenshots or exports were supplied for independent review.

| Console observation | Human-reported result |
|---|---|
| Instance allocation | `sokoladas-demo`: `VM.Standard.A1.Flex`, 2 OCPUs, 12 GB RAM |
| Always Free Ampere A1 allowance displayed | 3,000 OCPU-hours and 18,000 GB-hours per month, described by the Console as equivalent to 4 OCPUs and 24 GB RAM |
| Boot volume | One 47 GB boot volume; Boot Volumes view identifies it as Always Free |
| Additional block volumes | None present in the inspected compartment/region view |
| Cost Analysis period | September 1–September 7, 2026 |
| Cost To Date | €0.00 |
| Service costs | Compute €0.00; Block Storage €0.00; Virtual Cloud Network €0.00 |

The 47 GB Console value is retained as reported, alongside the earlier guest-observed 46.6 GiB disk and historical approximate 46 GB value; no exact unit/rounding reconciliation was performed. Absence of additional volumes applies only to the inspected compartment/region view, not all tenancy resources. Exact Console filters beyond the supplied date range and volume-view scope were not recorded.

This closes the remaining TODO 0 cost-verification item on the basis of human verification. It is not a guarantee of future zero cost, a tenancy-wide resource audit, or approval for paid resources. An explicit spending limit and ongoing cost-check cadence have not been supplied and remain open in [README.md](../README.md). The documentation update is Human accepted; the prior live inspection remains Human accepted.

## Live baseline inspection — 2026-09-07 — Human accepted

Scope: TODO section 0 inventory and workload/data discovery only, excluding cost/Free Tier verification. Connected as `marijus` to the human-confirmed address `152.70.25.153`. Remote timestamps span **12:30:42–12:31:36 UTC**. No OCI API, metadata-service, DNS, or other external-system inspection was performed; later TODO sections were not executed.

### Observed host and storage

| Check | Observed result | Limitation |
|---|---|---|
| SSH with explicit key, `BatchMode=yes`, `IdentitiesOnly=yes`, `StrictHostKeyChecking=yes`, `UpdateHostKeys=no`; `hostname`; `id` | Connection succeeded; hostname `sokoladas-demo`; `marijus` UID/GID 1002, groups `marijus`, `sudo`, `users` | No host-key bypass/update; successful access does not establish key-only server policy or usable sudo |
| `date -u`; `uptime` | September 7, 2026; uptime 18:38 at 12:30 UTC; load averages 0.17/0.12/0.10 | Remote clock reading; uptime/load are transient |
| `/etc/os-release`; `uname -m`; `uname -r`; `lscpu` | Ubuntu 26.04.1 LTS; `aarch64`; kernel `7.0.0-1010-oracle`; 2 online CPUs, ARM Neoverse-N1 | Guest observations do not independently verify OCI shape, OCPU allocation, or region |
| `free -h`; `swapon --show` | 11 GiB total and available RAM as rounded by the tool, 579 MiB used; 0 B swap and no active swap entries | Not an exact measurement of OCI allocated RAM; no swap decision/configuration made |
| `lsblk`; `df -hT`; `findmnt` | One visible 46.6 GiB disk `sda`; 45.6 GiB ext4 root partition, 923 MiB ext4 boot partition, 99 MiB EFI partition; root filesystem 45 GiB total, 2.8 GiB used, 42 GiB available (7% used) | Tool-rounded values; no additional disk or application/network mount identified in the inspected output; not proof about unattached OCI volumes |
| `ip -brief address`; `ip route show` | `enp0s6` has `10.0.0.52/26` and link-local IPv6; default route via `10.0.0.1` | Guest network view only; historical VCN/subnet/gateway names and cloud rules remain unverified |

The authorized public address was reachable over SSH during this inspection. Its dynamic/reserved status was not reverified; the historical record describes dynamic assignment. Reachability now does not guarantee the address later.

### Workloads and possible persistent data

- `systemctl list-units --type=service --state=running` listed 25 running units; `systemctl --failed` listed zero failed units. Visible services/processes included SSH, cron, chrony, logging/network services, snapd, Oracle Cloud Agent and its updater, rpcbind, iscsid, multipathd, ModemManager, fwupd, and unattended-upgrades. A running unattended-upgrades unit does not establish update policy or current patch status.
- `ps -eo user:20,comm --sort=user` showed OS/cloud-agent processes and inspection sessions, with no recognizable application, database, container-runtime, or reverse-proxy process. Command arguments and process environments were deliberately not collected. This is a point-in-time view, not a check of dormant jobs or all service definitions.
- `ss -lntu` showed TCP 22 and TCP/UDP 111 bound on IPv4/IPv6 wildcard addresses, DNS 53 on loopback, chrony UDP 323 on loopback, and DHCP UDP 68 on the private interface. No listeners on 80, 443, 5432, or common application ports appeared. Port 111 listeners coincide with running rpcbind; process ownership was not verified. Binding does not prove public reachability: no firewall inspection or external port scan was performed.
- The `dpkg-query` package/status listing contained no Docker, containerd, Podman, Node.js/npm, PostgreSQL server, MySQL server, Redis server, Nginx, or Caddy packages. Explicit `command -v` checks did not find `docker`, `podman`, `containerd`, `ctr`, `node`, `npm`, `pnpm`, `psql`, `postgres`, `redis-server`, `nginx`, or `caddy` in the remote shell PATH. `/var/run/docker.sock` was absent. This does not exclude custom or user-local installations; no Docker daemon was started or queried.
- Directory metadata/listings showed empty `/srv`, `/opt`, `/mnt`, `/media`, `/usr/local/bin`, and `/usr/local/sbin`. `/var/www`, `/var/lib/docker`, `/var/lib/containerd`, `/var/lib/postgresql`, `/var/lib/mysql`, and `/var/lib/redis` did not exist. `/var/lib` contained OS/package/cloud-agent state directories. No application data was identified in these locations.
- `/var/backups` contained `alternatives.tar.0`, `apt.extended_states.0`, and dpkg metadata backup filenames; contents were not read and these do not establish an application backup capability. `/home` contained directories for `marijus`, `ubuntu`, and `opc`. A depth-two directory-only search of `/home/marijus`, excluding `.ssh` and `.cache`, returned only the home directory; ordinary file contents and a complete home-file inventory were not inspected.
- Noninteractive `sudo -n -- ls -la` of `/root` and user homes, and `sudo -n -- du -xhd1` of home/system data locations, both failed with **interactive authentication is required**. No password was supplied, no authentication configuration changed, and no privileged directory/size results were obtained.

**Assessment:** no deployed application workload or application data was identified in the inspected views. Persistent OS/account/cloud-agent state and package metadata backups do exist. At inspection time, data value required owner confirmation and protected or otherwise uninspected paths could contain additional data; the subsequent owner confirmation below resolves the preservation requirement without extending the inspection evidence. Do not treat this inspection as permission to discard data or rebuild the server.

### Owner confirmation and acceptance — 2026-09-07

Marijus completed human review and accepted the scoped live baseline inspection. The owner confirms that this is a freshly provisioned demo VM with no pre-existing application or user data requiring preservation. Protected paths were not inspected and may contain normal OS/cloud-provider state, but no valuable pre-existing application data is expected there.

This is owner-provided context, not an observation of protected paths. OS configuration and repository-documented infrastructure work may be treated as reproducible until persistent application data is introduced. The current data-preservation question is resolved; future persistent application data requires a new preservation/backup assessment. This confirmation does not authorize destructive actions or live changes. No additional server inspection was performed for this update.

### Verification boundaries

The first SSH attempt was blocked by the local sandbox; the authorized retry succeeded. Host identity, OS/resources, mounts, process/service views, package names, PATH checks, sockets, and selected directory metadata were cross-checked. Missing paths and the negative Docker-socket test produced a nonzero discovery-command status; later explicit checks confirmed the missing tools/socket. The final command batch returned nonzero because sudo reads were denied; those checks remain incomplete rather than successful verification.

Only read-oriented remote commands were issued. No package/configuration writes, service restarts, or administrative mutations were performed. Normal SSH/sudo audit logging and filesystem access-time effects were not suppressed or audited. No secret files, application data contents, process environments, or authentication logs were collected. No full filesystem, scheduled-job, backup-content, or privileged audit was completed. Cost/eligibility and TODO sections 1 onward remain out of scope.

## Historical setup and access

### System update — 2026-09-06

Previously documented commands, retained as historical information rather than instructions to run now:

```bash
sudo apt update
sudo apt upgrade -y
```

The [September 6 change log](../CHANGELOG.md) reports completed package updates/upgrades, creation of `marijus`, addition to `sudo`, installation of an SSH public key, key-authenticated login, and sudo access. It records `ubuntu` retained as fallback and password SSH authentication not yet disabled.

The listed verification commands were `whoami` and `sudo whoami`, without captured outputs. These address identity and sudo behavior; they do not establish SSH authentication method or effective SSH policy. Key login success would not by itself establish key-only access. No fresh access verification occurred during documentation remediation.

## Current unknowns and prerequisites

| Area | Recorded limitation / prerequisite |
|---|---|
| SSH and accounts | Human hardening report confirms the six effective settings, fresh marijus/ubuntu key sessions, ubuntu passwordless sudo, and root rejection; owner subsequently verified marijus sudo entitlement `(ALL : ALL) ALL` using `sudo -l -U marijus`; account-specific SSH policy checks remain unverified |
| Recovery | Owner tested ubuntu key login/passwordless sudo and, separately, end-to-end OCI Serial Console login as marijus with the local Linux password on 2026-09-07. Serial Console provides recovery access independent of normal SSH; arbitrary OS/boot repair is not claimed |
| OCI networking | Human Console evidence above records primary VNIC, subnet, route, no NSGs, ephemeral public IP, and default Security List ingress. Default-list egress is human-reported unrestricted IPv4/stateful; Mac TCP 22 succeeded and TCP 111/80/443 timed out. Final human evidence recorded September 8 confirms exactly one attached list and stateful ingress; Section 3 is closed Human accepted. Gateway enabled flag and broader reachability remain unverified within the completion limits above |
| Host / containers | Listeners, firewall technology, and saved rules recorded in the network assessment above; loaded filter rules were subsequently supplied by Marijus, with the UDP 123 live-rule representations subsequently verified consistent by the owner. Earlier saved-file evidence remains historical; no fresh persistence comparison is claimed. September 8 Docker installation above establishes the rootful runtime, default data roots, bounded local logging and unchanged LXD installer. Docker added its runtime forwarding/NAT chains; saved firewall files remain unchanged. Future container publishing and reboot/reload behavior remain unverified |
| DNS / TLS / application | DNS/TLS uninspected; no application workload identified in the point-in-time views above, not an exhaustive deployment audit |
| Secrets | No storage/delivery mechanism selected; never put secret values in this inventory or verification output |
| Persistent data | OS/account state and package metadata backups observed; application data not identified in inspected paths. Owner confirms no pre-existing application/user data needs preservation; protected paths remain uninspected. Future application-data backup policy/restore capability remain open |

Before access-breaking changes, establish and record an available recovery path, relevant current access/fallback methods, and success checks; explicit human approval is required. Verify relevant OCI rules, host firewall behavior, and container-published ports together before claiming private service exposure. These prerequisites do not authorize inspection or changes themselves.

Before introducing data worth keeping, decide what is recreatable and what needs backup, then record the chosen backup location, cadence, retention, and restore check here. Do not treat demo status as proof that all data is disposable.

## Verification record format

For future scoped checks, record: **date; target; check; observed result; limitations**. Include useful sanitized evidence, distinguish reported from directly observed results, and never record secrets. Update this inventory when observations change; retain historical changes in [CHANGELOG.md](../CHANGELOG.md). Unperformed checks remain in [TODO.md](../TODO.md), not as successful verification entries.
