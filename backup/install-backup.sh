#!/usr/bin/env bash
# install-backup.sh — administrator operation: install the backup scripts,
# configuration skeleton and systemd units for sokoladas-demo.
#
# Run as root from a reviewed repository checkout:
#
#   sudo backup/install-backup.sh [--enable-timer]
#
# It never prints secret values. If no rclone configuration exists it generates
# a strong crypt password and salt, stores them obscured in
# /etc/sokoladas-staging/backup/rclone.conf, and writes the plaintext material to
# /etc/sokoladas-staging/backup/crypt-recovery.txt (0600) so the administrator
# can move it into the off-server recovery bundle. The Google OAuth token is
# installed later, after the browser authorization step.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR=/usr/local/sbin
CFG_DIR=/etc/sokoladas-staging/backup
ENABLE_TIMER=0
[[ "${1:-}" == "--enable-timer" ]] && ENABLE_TIMER=1

die() { printf 'install-backup: %s\n' "$*" >&2; exit 1; }
log() { printf 'install-backup: %s\n' "$*"; }

[[ "$(id -u)" -eq 0 ]] || die "must run as root"
command -v rclone >/dev/null 2>&1 || die "rclone is not installed (apt-get install -y rclone)"
command -v docker >/dev/null 2>&1 || die "docker is not installed"

# --- scripts ---------------------------------------------------------------

install -o root -g root -m 0755 "$SRC_DIR/sokoladas-backup.sh" "$BIN_DIR/sokoladas-backup"
install -o root -g root -m 0755 "$SRC_DIR/sokoladas-restore-verify.sh" "$BIN_DIR/sokoladas-restore-verify"
log "installed scripts to $BIN_DIR"

# --- configuration ---------------------------------------------------------

install -d -o root -g root -m 0700 "$CFG_DIR"
install -d -o root -g root -m 0700 /opt/sokoladas-staging/backup /opt/sokoladas-staging/backup/staging

if [[ ! -f "$CFG_DIR/backup.env" ]]; then
  install -o root -g root -m 0600 "$SRC_DIR/backup.env.example" "$CFG_DIR/backup.env"
  log "installed $CFG_DIR/backup.env (review it)"
fi

if [[ ! -f "$CFG_DIR/rclone.conf" ]]; then
  plain_password="$(openssl rand -base64 48 | tr -d '\n')"
  plain_salt="$(openssl rand -base64 48 | tr -d '\n')"
  obscured_password="$(rclone obscure "$plain_password")"
  obscured_salt="$(rclone obscure "$plain_salt")"
  umask 077
  cat >"$CFG_DIR/rclone.conf" <<CONF
[gdrive]
type = drive
scope = drive
root_folder_id =
token = {}

[crypt]
type = crypt
remote = gdrive:
filename_encryption = standard
directory_name_encryption = true
password = $obscured_password
password2 = $obscured_salt
CONF
  chmod 0600 "$CFG_DIR/rclone.conf"
  cat >"$CFG_DIR/crypt-recovery.txt" <<REC
sokoladas-demo backup crypt password (keep this offline; needed to decrypt backups)
crypt password: $plain_password
crypt salt:     $plain_salt
rclone remote [crypt] (obscured) is in $CFG_DIR/rclone.conf
REC
  chmod 0600 "$CFG_DIR/crypt-recovery.txt"
  unset plain_password plain_salt obscured_password obscured_salt
  log "generated crypt password/salt -> $CFG_DIR/crypt-recovery.txt (move it into the recovery bundle)"
fi

# --- systemd ---------------------------------------------------------------

install -o root -g root -m 0644 "$SRC_DIR/systemd/sokoladas-backup.service" /etc/systemd/system/sokoladas-backup.service
install -o root -g root -m 0644 "$SRC_DIR/systemd/sokoladas-backup.timer" /etc/systemd/system/sokoladas-backup.timer
systemctl daemon-reload
log "installed systemd units"

if [[ "$ENABLE_TIMER" == "1" ]]; then
  systemctl enable --now sokoladas-backup.timer
  log "enabled and started sokoladas-backup.timer"
else
  log "timer not enabled yet (enable after Google authorization: systemctl enable --now sokoladas-backup.timer)"
fi

log "next: complete the Google authorization procedure in docs/backups.md"
