# SapiensMetric backups (T-023)

Encrypted, off-server backup of the SapiensMetric closed-review stack, reusing the
**existing** Sokoladas rclone `crypt` remote but writing to a **separate** path.

> **Scope boundary:** the Sokoladas PostgreSQL dump does **not** cover
> SapiensMetric. SapiensMetric uses **MySQL 8.0.46**, not PostgreSQL, and has its
> own job, path, retention and restore procedure. Preserving one does not preserve
> the other.

## Design

| Aspect | Value |
|---|---|
| Script | `backup/sapiensmetric-backup.sh` |
| Entry point | `/usr/local/sbin/sapiensmetric-backup` (root) |
| Config | `/etc/sapiensmetric/backup/backup.env` (from `backup/sapiensmetric-backup.env.example`) |
| Remote | the existing `crypt:` remote → `sapiensmetric-backups/sets/` |
| rclone config | `/etc/sokoladas-staging/backup/rclone.conf` (root 0600; shared) |
| Set contents | `db.sql.gz` (MySQL logical dump), `config.tar.gz` (compose/images/hostenv/secrets/SOURCE_COMMIT), `metadata.json` (row counts), `sha256sums.txt`, `COMPLETE` |
| Cadence | daily ~03:30 Europe/Vilnius (`sapiensmetric-backup.timer`), offset from Sokoladas |
| Retention | latest 7 daily sets + 4 weekly sets (same policy as Sokoladas) |
| Encryption | client-side (rclone `crypt`) before upload |

The job holds only its own run lock; it does not take the Sokoladas deploy lock.

## Install (root, once)

```sh
sudo backup/sapiensmetric-backup-install.sh --enable-timer
sudo /usr/local/sbin/sapiensmetric-backup check-remote
```

Run the first backup and verify it end-to-end (isolated restore):

```sh
sudo /usr/local/sbin/sapiensmetric-backup run
sudo /usr/local/sbin/sapiensmetric-restore-verify run
```

## Scoped maintenance access (T-023)

`backup/bootstrap-sapiensmetric-maintenance.sh` (root, one-time) installs the
corrected scripts/config/units, creates the SELECT-only `sapiensmetric_backup`
MySQL account (password in `/etc/sapiensmetric/secrets/sm_backup_password`,
root `0600`), and enables the timer. It also installs four fixed, argument-less
wrappers and a `visudo`-validated sudoers rule so the agent's SSH account can run
**only**:

```text
/usr/local/sbin/sapiensmetric-maint-check
/usr/local/sbin/sapiensmetric-maint-status
/usr/local/sbin/sapiensmetric-maint-backup
/usr/local/sbin/sapiensmetric-maint-restore-verify
```

No `NOPASSWD:ALL`, no shell/installer execution, no Docker-group membership and no
generic `docker` sudo. The wrappers run with `env -i` and a fixed `PATH`, so paths
and configuration cannot be overridden by the caller. Revocation:

```sh
sudo rm -f /etc/sudoers.d/sapiensmetric-maintenance
sudo rm -f /usr/local/sbin/sapiensmetric-maint-*
sudo systemctl disable --now sapiensmetric-backup.timer
```

## MySQL restore procedure

`sapiensmetric-restore-verify` restores a set into a **throwaway** MySQL 8.0.46
container on `--network none` (no outbound, no published ports), compares row
counts against the set's `metadata.json`, writes an evidence report, and removes
the container and temporary directories. It never touches the live SapiensMetric
or Sokoladas databases.

```sh
sudo /usr/local/sbin/sapiensmetric-restore-verify run            # newest set
sudo /usr/local/sbin/sapiensmetric-restore-verify run 2026-10-13T003000Z
```

Evidence is written under `/opt/sapiensmetric-review/backup/restore-evidence/`.

To restore the **live** stack manually: stop the API (`docker compose -p
sapiensmetric-review --project-directory /opt/sapiensmetric-review stop api`),
restore `config.tar.gz` back into `/opt/sapiensmetric-review` and
`/etc/sapiensmetric/secrets`, recreate the database container/volume, load
`db.sql.gz`, then start the API and verify
`https://api.sapiensmetric.eu/health/ready` = 200. This is a reviewed procedure,
not yet exercised against the live stack.

## Limitations

- A durable scheduled off-host destination now exists via this job, but the first
  scheduled run and a restore test are **not yet observed**.
- The shared rclone `crypt` remote is a dependency on the Sokoladas backup setup;
  if its authorization lapses, both jobs skip (each leaves old sets untouched).
