# Section 8 — Encrypted off-server backups (Google Drive)

Implementation of automatic, encrypted off-server backups for the
`sokoladas-demo` deployment at `https://sokoladas.eu`, with a tested restore
path. Owned by `sm-oracle-infra`; scripts and systemd units live in
[`backup/`](../backup/).

## Design at a glance

| Concern | Choice |
|---|---|
| Transport | `rclone` with a `crypt` remote over a Google Drive remote |
| Destination | Google Drive `atsargines-kopijos/sokoladas` (pinned by folder id) |
| Schedule | `sokoladas-backup.timer`, daily ~03:00 `Europe/Vilnius` (persistent) |
| Retention | latest 7 successful daily sets + 4 weekly sets |
| Encryption | rclone `crypt`, client-side before upload (filenames and content) |
| Coordination | shared `flock` on the deploy lock (`stage`/`release`/`rollback`) |
| Failure notice | existing Resend channel (optional `NOTIFY_TO`) |

Scripts: `/usr/local/sbin/sokoladas-backup` (create/upload/verify/prune) and
`/usr/local/sbin/sokoladas-restore-verify` (isolated restore test). Both
root-owned; the `deploy` account's permissions are unchanged.

## What a backup set contains

Each set is a directory named `YYYY-MM-DDTHHMMSSZ` (UTC) uploaded under
`sokoladas-backups/sets/<name>/`:

| File | Contents |
|---|---|
| `db.dump` | Consistent `pg_dump -Fc` logical dump of `sokoladas_staging` |
| `media.tar.gz` | The persistent media volume (`products/`, i.e. `/media/products/*`) |
| `config.tar.gz` | `/etc/sokoladas-staging/{hostenv,secrets}`, the applied state, the applied release manifest, `compose.yaml` and the template version |
| `metadata.json` | Row counts (users, categories, products, tags, ratings, media references), release id, image digests, file sizes |
| `sha256sums.txt` | SHA-256 of the three artifacts |
| `COMPLETE` | Completion marker written only after a verified upload |

**Included:** the database, the referenced uploaded media, and the configuration
and host secrets needed to reconstruct the deployment (including the applied
release manifest).
**Excluded:** temporary files, Docker image layers / build cache, `pg_data`
raw files, `/var/backups`, and the live backup OAuth credentials
(`/etc/sokoladas-staging/backup/` is never archived). Secrets are only ever
present **inside** the encrypted archive.

The snapshot is consistent and self-checked: the set fails before upload if any
media file referenced by the database snapshot is not present in the media
archive, and the database is dumped first so referenced files exist when the
media archive is taken.

## Encryption and remotes

`/etc/sokoladas-staging/backup/rclone.conf` (root, `0600`) defines two remotes:

```ini
[gdrive]
type = drive
scope = drive
root_folder_id = <pinned destination folder id>
token = {<Google OAuth token>}

[crypt]
type = crypt
remote = gdrive:
filename_encryption = standard
directory_name_encryption = true
password = <obscured crypt password>
password2 = <obscured salt>
```

A backup set is uploaded to `crypt:`; rclone encrypts names and content before
any byte reaches Google. Nothing is stored on Drive in plaintext.

## Google authorization (one-time, operator)

This is the only step that requires a browser. Use the account
`odisejas.laertas@gmail.com`. Do **not** share the Google password; do **not**
paste the resulting token into chat.

1. **On the machine with a browser** (the operator's machine, where `rclone` is
   installed), run:
   ```sh
   rclone authorize drive > ~/sokoladas-drive-token.json
   ```
   A browser opens; sign in as `odisejas.laertas@gmail.com` and grant access.
   The OAuth token is written to `~/sokoladas-drive-token.json` and is **not**
   printed.

2. **Transfer the token to the server** over the existing SSH workflow (the
   token never appears in chat or shell history output):
   ```sh
   ssh ubuntu@sokoladas.eu 'sudo /usr/local/sbin/sokoladas-backup set-token' < ~/sokoladas-drive-token.json
   ```

3. **Pin the destination folder** (verifies the existing folder identity; it
   refuses rather than creating a duplicate or guessing):
   ```sh
   ssh ubuntu@sokoladas.eu 'sudo /usr/local/sbin/sokoladas-backup resolve-folder'
   ```

4. **Verify the remote and enable the schedule:**
   ```sh
   ssh ubuntu@sokoladas.eu 'sudo /usr/local/sbin/sokoladas-backup check-remote'
   ssh ubuntu@sokoladas.eu 'sudo systemctl enable --now sokoladas-backup.timer'
   ```

5. Optionally delete the local token file once installed, and set `NOTIFY_TO`
   in `/etc/sokoladas-staging/backup/backup.env`.

### OAuth scope — actual meaning

The remote uses `scope = drive`, which grants full read/write access to the
account's Google Drive. This is intentional: Google's narrower
`drive.file` scope can only see files and folders the app itself created, so it
**cannot** access the pre-existing `atsargines-kopijos/sokoladas` folder. A
configured `root_folder_id` restricts **where rclone operates**, but it does
**not** narrow the token's permission — the token still has full Drive access.
If full-Drive scope is unacceptable, the alternative is to let the app create
its own folder (then `drive.file` works) and point `root_folder_id` at that new
folder; that creates a new folder rather than using the existing one.

## Schedule

`sokoladas-backup.timer` runs `sokoladas-backup.service` daily at ~03:00
`Europe/Vilnius` (`OnCalendar=*-*-* 03:00:00 Europe/Vilnius`,
`RandomizedDelaySec=300`, `Persistent=true`). Inspect with:

```sh
systemctl list-timers sokoladas-backup.timer
systemctl status sokoladas-backup.service
journalctl -u sokoladas-backup.service
tail -n 20 /var/log/sokoladas-backup.log
```

## Retention

After a verified upload, `sokoladas-backup` deletes only **successful** sets
(those with a `COMPLETE` marker) under the managed prefix
`sokoladas-backups/sets/`: it keeps the newest set of each of the most recent
7 UTC days and the newest set of each of the most recent 4 ISO weeks. It never
touches incomplete/failed sets, never touches anything outside the managed
prefix, and never uses a broad sync/purge. Preview the decision with:

```sh
sudo /usr/local/sbin/sokoladas-backup retention
```

## Integrity, failures and retries

- rclone verifies object integrity during transfer; the set is then
  re-downloaded and checksum-verified (`sha256sum -c`) before the `COMPLETE`
  marker is written. Pruning happens only after that.
- Overlapping runs are prevented by an exclusive run lock; a shared lock on the
  deploy lock avoids snapshotting during a release/migration.
- A failed run never deletes the last good backup; failures are recorded in
  `/var/log/sokoladas-backup.log` and `backup/state.log` without secrets, and a
  failure email is sent via the existing Resend channel when `NOTIFY_TO` is set.
- Disk space is checked before a run (`MIN_FREE_MB`).
- If the Google remote is not authorized yet, the service logs `NOT_AUTHORIZED`
  and exits 0 (no failure spam) until authorization completes.

## Manual backup

```sh
sudo /usr/local/sbin/sokoladas-backup run       # snapshot + upload + verify + prune
sudo /usr/local/sbin/sokoladas-backup snapshot  # local set only, no upload
sudo /usr/local/sbin/sokoladas-backup status
```

## Restore test / disaster recovery

The restore test runs in isolation and never touches the live database or media:

```sh
sudo /usr/local/sbin/sokoladas-restore-verify run <set-name>
```

It downloads and decrypts the set, starts a throwaway PostgreSQL container on
`--network none` (no outbound email or external integrations, no published
ports), restores the dump into a separate database with `pg_restore
--no-owner --no-privileges`, extracts the media separately, and compares row
counts and referenced media against the set's recorded `metadata.json`. A report
is retained under `/opt/sokoladas-staging/backup/restore-evidence/`; only the
throwaway container and extraction dirs are removed.

Disaster recovery on a rebuilt host:

1. Restore the host/Docker per the infrastructure bootstrap; restore the release
   directory and `/etc/sokoladas-staging` from `config.tar.gz`.
2. Restore the database: start PostgreSQL, create `sokoladas_staging`, then
   `pg_restore` (owner/login roles `sokoladas_app`, `sokoladas_migration`;
   extension `plpgsql` only).
3. Extract `media.tar.gz` into the `media_data` volume (`products/`,
   UID `10001:10001`).
4. Recreate the services and verify with the standard release health checks.

The backup set records the PostgreSQL roles to recreate and the only extension in
use; the archive's `config.tar.gz` holds the exact secrets and applied manifest.

## Recovery bundle (keep offline)

The material required to **decrypt** backups is kept outside the Oracle VM, in a
protected directory on the operator's local machine:

```text
~/sokoladas-backup-recovery/
  crypt-recovery.txt   # crypt password + salt (plaintext)
  rclone.conf          # the [crypt] remote config (contains the same secret)
  README.md            # where the live token lives and how to restore
```

This directory is mode `0700` and is **not** in Git. Copy it into the owner's
password manager (or an offline encrypted medium) and store the two items
independently of the server: without `crypt password`/`crypt salt`, the Drive
objects are unreadable. The live OAuth token lives only in
`/etc/sokoladas-staging/backup/rclone.conf` on the server and is deliberately
excluded from routine backup archives; if it is lost, re-run the Google
authorization procedure (the crypt password is still required to read old sets).

## Security summary

- Secrets are only ever inside the encrypted archive or the `0600` server
  config; nothing secret is committed, printed or logged.
- The backup scripts and units are root-owned; `deploy` permissions are
  unchanged.
- Retention is limited to `sokoladas-backups/sets/`; no broad Drive operations.
