# Scoped unattended deployment entry point

This directory contains the root-owned entry point that replaces the former
unrestricted `deploy ALL=(ALL) NOPASSWD:ALL` sudo grant on `sokoladas-demo`.

| File | Installed to | Purpose |
|---|---|---|
| `sokoladas-deploy` | `/usr/local/sbin/sokoladas-deploy` (root:root 0755) | Validated deployment entry point |
| `90-sokoladas-deploy` | `/etc/sudoers.d/90-sokoladas-deploy` (root:root 0440) | Sudoers rule allowing only that entry point |

## What the `deploy` account may do

Only three root operations, via the entry point:

```sh
ssh deploy@sokoladas.eu 'sudo -n /usr/local/sbin/sokoladas-deploy status'
ssh deploy@sokoladas.eu 'sudo -n /usr/local/sbin/sokoladas-deploy release <release-id>'
ssh deploy@sokoladas.eu 'sudo -n /usr/local/sbin/sokoladas-deploy rollback <release-id|previous>'
```

Everything else is denied: no general sudo, no shell, editor, `systemctl`, or
direct `docker`. The account is not in the `docker` group.

## Security model

- The caller's environment is discarded (`env -i`), so `SOKOLADAS_*` / `COMPOSE_*`
  overrides cannot redirect the compose file, env files, volumes, or state and
  evidence paths. `Defaults:deploy !setenv` also refuses `sudo VAR=value …`.
- The release id is a strict slash-free token (`^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`)
  and the resolved directory must stay under `/opt/sokoladas-staging/releases`.
- The release directory and **every file in it** must be root-owned and not
  group/other writable; a release-writable or group/other-writable config
  (compose, proxy, db init, certbot, manifest) is refused.
- The manifest is validated: schema 1, matching `releaseId`, `web`/`api` image
  references restricted to `ghcr.io/marijustechin/smshop-web` /
  `ghcr.io/marijustechin/smshop-api` pinned by immutable `@sha256:<64hex>`,
  `linux/arm64` platform, and a 40-hex `source.commit`.
- The entry point never runs a shell, editor, `docker`, or `systemctl` on the
  caller's behalf.

## Install / update (root)

```sh
sudo install -o root -g root -m 0755 deploy/entrypoint/sokoladas-deploy /usr/local/sbin/sokoladas-deploy
sudo visudo -cf deploy/entrypoint/90-sokoladas-deploy
sudo install -o root -g root -m 0440 deploy/entrypoint/90-sokoladas-deploy /etc/sudoers.d/90-sokoladas-deploy
```

## Recovery

`ubuntu` retains independent SSH and passwordless sudo access and is the recovery
path; the `deploy` path is not required for recovery. If the scoped rule must be
rolled back, as `ubuntu`:

```sh
sudo cp -a /root/90-sokoladas-deploy.pre-scoped.bak /etc/sudoers.d/90-sokoladas-deploy
```

The pre-change grant is archived at
`/root/90-sokoladas-deploy.pre-scoped.bak`. The deployment itself can always be
run directly by an administrator:

```sh
cd /opt/sokoladas-staging/releases/<id> && sudo ./deploy.sh release <id>
```

## Remaining manual (privileged) steps

Staging a release is intentionally **not** delegated to `deploy`:

1. Stage the release directory root-owned under
   `/opt/sokoladas-staging/releases/<release-id>/` (config tree + the approved
   `releases/<release-id>.json` manifest + host-only `smtp.env`/`google.env`).
2. Ensure no file in that tree is deploy-owned or group/other writable.
3. Then the `deploy` account can run `release <release-id>` unattended.
