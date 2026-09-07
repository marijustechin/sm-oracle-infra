# Sokoladas Demo Server

## Evidence and currency

This is the authoritative recorded inventory, not guaranteed live state. The baseline below was consolidated from existing repository documentation on 2026-09-07 without inspecting the server, OCI, DNS, or other external systems. Original observation dates are unknown unless stated. Treat changeable values as historical observations until verified in an explicitly scoped task.

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
| SSH and accounts | Effective authentication/root-login settings, current account privileges, and usable access methods need scoped verification |
| Recovery | `ubuntu` was retained as fallback, but current usability and OCI console recovery procedure are not established; another account alone does not prove recovery from network/sshd failure |
| OCI networking | Actual security-list/NSG rules and their attachment/effective exposure have not been recorded |
| Host / containers | Host firewall, listening ports, Docker installation, and published ports have not been established by repository evidence |
| DNS / TLS / application | Current records, certificates, and deployment state are not established here |
| Secrets | No storage/delivery mechanism selected; never put secret values in this inventory or verification output |
| Persistent data | Existing valuable data, backup destination/cadence/retention, and restore capability are unknown |

Before access-breaking changes, establish and record an available recovery path, relevant current access/fallback methods, and success checks; explicit human approval is required. Verify relevant OCI rules, host firewall behavior, and container-published ports together before claiming private service exposure. These prerequisites do not authorize inspection or changes themselves.

Before introducing data worth keeping, decide what is recreatable and what needs backup, then record the chosen backup location, cadence, retention, and restore check here. Do not treat demo status as proof that all data is disposable.

## Verification record format

For future scoped checks, record: **date; target; check; observed result; limitations**. Include useful sanitized evidence, distinguish reported from directly observed results, and never record secrets. Update this inventory when observations change; retain historical changes in [CHANGELOG.md](../CHANGELOG.md). Unperformed checks remain in [TODO.md](../TODO.md), not as successful verification entries.
