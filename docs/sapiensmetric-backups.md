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
sudo install -m 0755 backup/sapiensmetric-backup.sh /usr/local/sbin/sapiensmetric-backup
sudo install -d -m 0700 /etc/sapiensmetric/backup
sudo install -m 0600 backup/sapiensmetric-backup.env.example /etc/sapiensmetric/backup/backup.env
sudo install -m 0644 backup/systemd/sapiensmetric-backup.service /etc/systemd/system/
sudo install -m 0644 backup/systemd/sapiensmetric-backup.timer   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now sapiensmetric-backup.timer
sudo /usr/local/sbin/sapiensmetric-backup check-remote
```

Run once manually to establish the baseline:

```sh
sudo /usr/local/sbin/sapiensmetric-backup run
sudo /usr/local/sbin/sapiensmetric-backup status
```

## MySQL restore procedure

Restores are performed into a **fresh** database; never restore over the live
database in place. The set is downloaded, verified, then loaded into a new MySQL
instance and checked against `metadata.json`.

```sh
# 1) Fetch and verify the set (root).
set=2026-10-13T003000Z
sudo rclone --config /etc/sokoladas-staging/backup/rclone.conf \
  copy "crypt:sapiensmetric-backups/sets/$set" "/root/smens-restore/$set"
( cd "/root/smens-restore/$set" && sudo sha256sum -c sha256sums.txt )

# 2) Start a throwaway MySQL 8.0.46 with the restored data (no published ports).
docker run -d --rm --name smens-restore-db \
  -e MYSQL_ROOT_PASSWORD=restore -e MYSQL_DATABASE=restore \
  --network none mysql:8.0.46
# (allow it to initialise, or use --network none + docker exec for the dump)

# 3) Load the dump.
sudo gunzip -c "/root/smens-restore/$set/db.sql.gz" \
  | docker exec -i smens-restore-db sh -c 'exec mysql -uroot -prestore restore'

# 4) Compare row counts to the recorded metadata.
docker exec smens-restore-db sh -c \
  'mysql -N -B -uroot -prestore restore -e "SELECT (SELECT COUNT(*) FROM users) AS users, (SELECT COUNT(*) FROM assessment_attempts) AS attempts"'
cat "/root/smens-restore/$set/metadata.json"

# 5) Clean up the throwaway database and the downloaded set.
docker rm -f smens-restore-db
sudo rm -rf "/root/smens-restore/$set"
```

To restore the **live** stack: stop the API (`docker compose -p sapiensmetric-review
--project-directory /opt/sapiensmetric-review stop api`), restore `config.tar.gz`
back into `/opt/sapiensmetric-review` and `/etc/sapiensmetric/secrets`, recreate the
database container/volume, load `db.sql.gz`, then start the API and verify
`https://api.sapiensmetric.eu/health/ready` = 200. This is a reviewed procedure,
**not yet exercised live**; treat the first restore as unverified until performed.

## Limitations

- A durable scheduled off-host destination now exists via this job, but the first
  scheduled run and a restore test are **not yet observed**.
- The shared rclone `crypt` remote is a dependency on the Sokoladas backup setup;
  if its authorization lapses, both jobs skip (each leaves old sets untouched).
