# Scoped unattended deployment entry point

This directory contains the root-owned entry point that replaces the former
unrestricted `deploy ALL=(ALL) NOPASSWD:ALL` sudo grant on `sokoladas-demo`,
plus the two administrator tools that install the trusted template and repair an
already-staged release script.

| File | Installed to | Purpose |
|---|---|---|
| `sokoladas-deploy` | `/usr/local/sbin/sokoladas-deploy` (root:root 0755) | Validated `status`/`stage`/`release`/`rollback` entry point |
| `90-sokoladas-deploy` | `/etc/sudoers.d/90-sokoladas-deploy` (root:root 0440) | Sudoers rule allowing only that entry point |
| `install-template.sh` | *(admin tool, not installed)* | Install/refresh the trusted template and host-env |
| `install-release-script.sh` | *(admin tool, not installed)* | Replace only `deploy.sh` in an existing release |

## What the `deploy` account may do

Only four root operations, via the entry point:

```sh
ssh deploy@sokoladas.eu 'sudo -n /usr/local/sbin/sokoladas-deploy status'
ssh deploy@sokoladas.eu 'sudo -n /usr/local/sbin/sokoladas-deploy stage <release-id>' < manifest.json
ssh deploy@sokoladas.eu 'sudo -n /usr/local/sbin/sokoladas-deploy release <release-id>'
ssh deploy@sokoladas.eu 'sudo -n /usr/local/sbin/sokoladas-deploy rollback <release-id|previous>'
```

`stage` reads the manifest from stdin, so a manifest file never has to be placed
on the host by an administrator. `release` deploys an already-staged release.

Everything else is denied: no general sudo, no shell, editor, `systemctl`, or
direct `docker`. The account is not in the `docker` group.

## Ordinary release workflow

```text
CI publishes build manifest
  -> operator adds the staging releaseId and reviews the manifest
  -> deploy: sokoladas-deploy stage <id> < manifest.json     (builds the release dir)
  -> deploy: sokoladas-deploy release <id>                    (pull, migrate, start, verify)
  -> deploy: sokoladas-deploy status
  -> deploy: sokoladas-deploy rollback previous               (if needed)
```

`stage` only builds a root-owned release directory from the trusted template; it
pulls no images and changes nothing that is running. `release` is the only step
that touches the live stack.

## Security model

- Caller environment discarded (`env -i`); `Defaults:deploy env_reset` and
  `Defaults:deploy !setenv` also refuse `sudo VAR=value …`.
- `stage` accepts only a bounded JSON manifest on stdin (≤ 64 KiB), written to a
  private root-owned temporary file and validated before use. No scripts,
  archives, Compose files or caller-specified paths are accepted.
- Manifest validation: schema 1; matching `releaseId`; `source.repository` fixed
  to `github.com/marijustechin/smshop` with a 40-hex commit; `web`/`api` image
  references restricted to `ghcr.io/marijustechin/smshop-web` /
  `ghcr.io/marijustechin/smshop-api` pinned by immutable `@sha256:<64hex>`;
  `linux/arm64`; and unsupported fields at any level are rejected.
- The release id is a strict slash-free token
  (`^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`) and the resolved directory must stay
  under `/opt/sokoladas-staging/releases`.
- The release directory and **every file in it** must be root-owned and not
  group/other writable, with no symlinks or special files.
- The trusted template (`/opt/sokoladas-staging/template`) and the non-secret
  host-env directory (`/etc/sokoladas-staging/hostenv`) are root-owned and are
  the only sources used to construct a release.
- `stage`, `release` and `rollback` share one root-owned lock
  (`/opt/sokoladas-staging/state/deploy.lock`), so they cannot run concurrently.
- The entry point never runs a shell, editor, `docker`, or `systemctl` on the
  caller's behalf.

## Administrator operations

### Install or refresh the trusted template (root/`ubuntu`)

```sh
sudo deploy/entrypoint/install-template.sh <repo-deploy-dir> [host-env-src]
```

- Copies `compose.yaml`, `deploy.sh`, `stage.sh`, `proxy/`, `db/`, `certbot/`,
  `catalog-import/`, `scripts/resolve_release_manifest.py`, the `*.example`
  files and `releases/{README.md,example-release.json}` into
  `/opt/sokoladas-staging/template`, root-owned and not group/other writable.
- Writes `VERSION` (the infra commit, or a content hash outside a Git checkout),
  which every staged release records.
- Seeds `/etc/sokoladas-staging/hostenv/{smtp.env,google.env}` on first install
  (from `host-env-src`, e.g. an existing release directory) and preserves them
  on later refreshes. These files are **non-secret**; the password/client secrets
  remain under `/etc/sokoladas-staging/secrets/`.

Template refreshes are the only administrator operation required for ordinary
application releases, and are needed only when the deployment implementation
itself changes.

### Repair the deploy script of an already-staged release

```sh
sudo deploy/entrypoint/install-release-script.sh <release-id>
```

Replaces only `<release-id>/deploy.sh` with the trusted template's `deploy.sh`
and refuses to proceed if any other file in the release directory would change.
Use this to carry a `deploy.sh` fix into a release staged before the fix; the
release's manifest, `images.env`, rollback target and evidence are untouched.
This is a targeted repair, not a rebuild: historical release directories are
never silently rebuilt or replaced.

## Install / update the entry point (root)

```sh
sudo install -o root -g root -m 0755 deploy/entrypoint/sokoladas-deploy /usr/local/sbin/sokoladas-deploy
sudo visudo -cf deploy/entrypoint/90-sokoladas-deploy
sudo install -o root -g root -m 0440 deploy/entrypoint/90-sokoladas-deploy /etc/sudoers.d/90-sokoladas-deploy
```

## Recovery

`ubuntu` retains independent SSH and passwordless sudo access and is the recovery
path; the `deploy` path is not required for recovery, and unrestricted sudo is
never restored. If the scoped rule must be re-installed, use the reviewed
`sokoladas-deploy` entry point and `90-sokoladas-deploy` file above. The
deployment can always be run directly by an administrator:

```sh
cd /opt/sokoladas-staging/releases/<id> && sudo ./deploy.sh release <id>
```

The pre-change grant is archived at `/root/90-sokoladas-deploy.pre-scoped.bak`
for historical reference only; do **not** restore it (it re-grants unrestricted
root).
