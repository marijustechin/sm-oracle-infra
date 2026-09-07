# Infrastructure Change Log

## 2026-09-07

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
