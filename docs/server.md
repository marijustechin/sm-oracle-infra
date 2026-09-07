# Sokoladas Demo Server

## Evidence and currency

This is the authoritative recorded inventory, not guaranteed live state. The historical OCI baseline below was consolidated from existing repository documentation on 2026-09-07 without external inspection. A subsequent authorized read-only SSH inspection on the same date established the separate live observations below. Original historical observation dates remain unknown unless stated. Live observations are point-in-time evidence, not configuration guarantees.

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
| SSH and accounts | `marijus` SSH access and group membership observed above; noninteractive sudo denied. Effective authentication/root-login policy, full privileges, and fallback usability remain unverified |
| Recovery | `ubuntu` was retained as fallback, but current usability and OCI console recovery procedure are not established; another account alone does not prove recovery from network/sshd failure |
| OCI networking | Actual security-list/NSG rules and their attachment/effective exposure have not been recorded |
| Host / containers | Listeners and negative runtime/package/PATH checks recorded above; firewall rules, dormant/custom workloads, and complete container-installation status remain unverified |
| DNS / TLS / application | DNS/TLS uninspected; no application workload identified in the point-in-time views above, not an exhaustive deployment audit |
| Secrets | No storage/delivery mechanism selected; never put secret values in this inventory or verification output |
| Persistent data | OS/account state and package metadata backups observed; application data not identified in inspected paths. Owner confirms no pre-existing application/user data needs preservation; protected paths remain uninspected. Future application-data backup policy/restore capability remain open |

Before access-breaking changes, establish and record an available recovery path, relevant current access/fallback methods, and success checks; explicit human approval is required. Verify relevant OCI rules, host firewall behavior, and container-published ports together before claiming private service exposure. These prerequisites do not authorize inspection or changes themselves.

Before introducing data worth keeping, decide what is recreatable and what needs backup, then record the chosen backup location, cadence, retention, and restore check here. Do not treat demo status as proof that all data is disposable.

## Verification record format

For future scoped checks, record: **date; target; check; observed result; limitations**. Include useful sanitized evidence, distinguish reported from directly observed results, and never record secrets. Update this inventory when observations change; retain historical changes in [CHANGELOG.md](../CHANGELOG.md). Unperformed checks remain in [TODO.md](../TODO.md), not as successful verification entries.
