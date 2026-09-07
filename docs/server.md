# Sokoladas Demo Server

## Evidence and currency

This is the authoritative recorded inventory, not guaranteed live state. The historical OCI baseline below was consolidated from existing repository documentation on 2026-09-07 without external inspection. A subsequent authorized read-only SSH inspection on the same date established the separate live observations below. Original historical observation dates remain unknown unless stated. Live observations are point-in-time evidence, not configuration guarantees.

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
| OCI networking | Actual security-list/NSG rules and their attachment/effective exposure have not been recorded |
| Host / containers | Listeners and negative runtime/package/PATH checks recorded above; firewall rules, dormant/custom workloads, and complete container-installation status remain unverified |
| DNS / TLS / application | DNS/TLS uninspected; no application workload identified in the point-in-time views above, not an exhaustive deployment audit |
| Secrets | No storage/delivery mechanism selected; never put secret values in this inventory or verification output |
| Persistent data | OS/account state and package metadata backups observed; application data not identified in inspected paths. Owner confirms no pre-existing application/user data needs preservation; protected paths remain uninspected. Future application-data backup policy/restore capability remain open |

Before access-breaking changes, establish and record an available recovery path, relevant current access/fallback methods, and success checks; explicit human approval is required. Verify relevant OCI rules, host firewall behavior, and container-published ports together before claiming private service exposure. These prerequisites do not authorize inspection or changes themselves.

Before introducing data worth keeping, decide what is recreatable and what needs backup, then record the chosen backup location, cadence, retention, and restore check here. Do not treat demo status as proof that all data is disposable.

## Verification record format

For future scoped checks, record: **date; target; check; observed result; limitations**. Include useful sanitized evidence, distinguish reported from directly observed results, and never record secrets. Update this inventory when observations change; retain historical changes in [CHANGELOG.md](../CHANGELOG.md). Unperformed checks remain in [TODO.md](../TODO.md), not as successful verification entries.
