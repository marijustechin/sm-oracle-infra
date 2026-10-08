# Backup tooling

Encrypted off-server backups for `sokoladas-demo`. See
[`../docs/backups.md`](../docs/backups.md) for the full design, the one-time
Google authorization procedure, the schedule, retention, failure handling, the
recovery bundle and disaster recovery.

| File | Purpose |
|---|---|
| `sokoladas-backup.sh` | Create/upload/verify/prune a backup set (installed as `/usr/local/sbin/sokoladas-backup`) |
| `sokoladas-restore-verify.sh` | Isolated download + restore + verification (installed as `/usr/local/sbin/sokoladas-restore-verify`) |
| `install-backup.sh` | Administrator installer: scripts, config skeleton, crypt password, systemd units |
| `backup.env.example` | Non-secret configuration (installed to `/etc/sokoladas-staging/backup/backup.env`) |
| `rclone.conf.example` | Documents the `drive` + `crypt` remotes (no secrets) |
| `systemd/sokoladas-backup.{service,timer}` | Daily ~03:00 `Europe/Vilnius` run |

Nothing here contains secrets. The live `rclone.conf` (OAuth token + crypt
password) and the plaintext recovery material live only on the host / in the
operator's off-server recovery bundle.
