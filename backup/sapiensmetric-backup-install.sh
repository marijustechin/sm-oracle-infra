#!/usr/bin/env bash
# sapiensmetric-backup-install — administrator operation: install the
# SapiensMetric backup script, configuration and systemd units.
#
# Run as root from a reviewed repository/backup bundle:
#
#   sudo sapiensmetric-backup-install.sh [--enable-timer] [--run-now]
#
# It reuses the EXISTING Sokoladas rclone `crypt` remote configuration
# (/etc/sokoladas-staging/backup/rclone.conf) with a separate destination path;
# it does not create or modify the Sokoladas backup configuration or sets.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR=/usr/local/sbin
CFG_DIR=/etc/sapiensmetric/backup
SHARED_RCLONE=/etc/sokoladas-staging/backup/rclone.conf
ENABLE_TIMER=0
RUN_NOW=0
for arg in "$@"; do
  case "$arg" in
    --enable-timer) ENABLE_TIMER=1 ;;
    --run-now) RUN_NOW=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

die() { printf 'install: %s\n' "$*" >&2; exit 1; }
log() { printf 'install: %s\n' "$*"; }

[[ "$(id -u)" -eq 0 ]] || die "must run as root"
command -v rclone >/dev/null 2>&1 || die "rclone is not installed"
command -v docker >/dev/null 2>&1 || die "docker is not installed"

# --- scripts ---------------------------------------------------------------
install -o root -g root -m 0755 "$SRC_DIR/sapiensmetric-backup.sh" "$BIN_DIR/sapiensmetric-backup"
install -o root -g root -m 0755 "$SRC_DIR/sapiensmetric-restore-verify.sh" "$BIN_DIR/sapiensmetric-restore-verify"
log "installed scripts to $BIN_DIR"

# --- configuration ---------------------------------------------------------
install -d -o root -g root -m 0700 "$CFG_DIR"
install -d -o root -g root -m 0700 /opt/sapiensmetric-review/backup /opt/sapiensmetric-review/backup/staging

if [[ ! -f "$CFG_DIR/backup.env" ]]; then
  install -o root -g root -m 0600 "$SRC_DIR/sapiensmetric-backup.env.example" "$CFG_DIR/backup.env"
  log "installed $CFG_DIR/backup.env"
fi

[[ -f "$SHARED_RCLONE" ]] || log "WARNING: $SHARED_RCLONE not found; the remote will be unavailable until the Sokoladas rclone config exists"
log "using the shared rclone config: $SHARED_RCLONE"

# --- systemd ---------------------------------------------------------------
install -o root -g root -m 0644 "$SRC_DIR/systemd/sapiensmetric-backup.service" /etc/systemd/system/sapiensmetric-backup.service
install -o root -g root -m 0644 "$SRC_DIR/systemd/sapiensmetric-backup.timer" /etc/systemd/system/sapiensmetric-backup.timer
systemctl daemon-reload
if [[ "$ENABLE_TIMER" -eq 1 ]]; then
  systemctl enable --now sapiensmetric-backup.timer
  log "enabled and started sapiensmetric-backup.timer"
else
  log "timer installed but not enabled (re-run with --enable-timer, or run it manually)"
fi

if [[ "$RUN_NOW" -eq 1 ]]; then
  log "running the first backup"
  "$BIN_DIR/sapiensmetric-backup" run
fi
