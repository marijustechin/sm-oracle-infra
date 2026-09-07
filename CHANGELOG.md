# Infrastructure Change Log

## 2026-09-07

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
