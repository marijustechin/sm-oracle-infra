#!/usr/bin/env bash
# bootstrap-sapiensmetric-maintenance — one-time root bootstrap that (T-023):
#   * installs the corrected SapiensMetric backup/restore-verify scripts, config
#     and systemd timer;
#   * creates a SELECT-only MySQL backup account and stores its password in a
#     root-only file;
#   * installs four fixed wrappers and a narrowly scoped sudoers rule so the
#     agent's SSH account can run ONLY those wrappers without a password.
#
# It never grants NOPASSWD:ALL, unrestricted shell/installer execution, Docker
# group membership, or generic docker sudo access. Wrappers take no arguments and
# run with a stripped environment. Sudoers is validated with `visudo -cf` before
# activation.
#
# Run as root from the staged bundle:
#   sudo bash bootstrap-sapiensmetric-maintenance.sh [AGENT_USER]
#
# Revocation:
#   sudo rm -f /etc/sudoers.d/sapiensmetric-maintenance
#   sudo rm -f /usr/local/sbin/sapiensmetric-maint-*
#   (Backups stay enabled by design; do not disable sapiensmetric-backup.timer.)
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_USER="${1:-marijus}"
BIN=/usr/local/sbin
CFG_DIR=/etc/sapiensmetric/backup
SECRETS=/etc/sapiensmetric/secrets
DB_CONTAINER=sapiensmetric-review-db-1
HOSTENV=/opt/sapiensmetric-review/hostenv
SUDOERS_FILE=/etc/sudoers.d/sapiensmetric-maintenance
WRAPPERS=(sapiensmetric-maint-check sapiensmetric-maint-status sapiensmetric-maint-backup sapiensmetric-maint-restore-verify sapiensmetric-maint-api-update sapiensmetric-maint-api-role-check)

die() { printf 'bootstrap: %s\n' "$*" >&2; exit 1; }
log() { printf 'bootstrap: %s\n' "$*"; }

[[ "$(id -u)" -eq 0 ]] || die "must run as root"
command -v visudo >/dev/null 2>&1 || die "visudo not found"
id "$AGENT_USER" >/dev/null 2>&1 || die "agent user not found: $AGENT_USER"

# --- 1. scripts, config, systemd -------------------------------------------
install -o root -g root -m 0755 "$SRC_DIR/sapiensmetric-backup.sh" "$BIN/sapiensmetric-backup"
install -o root -g root -m 0755 "$SRC_DIR/sapiensmetric-restore-verify.sh" "$BIN/sapiensmetric-restore-verify"
install -o root -g root -m 0755 "$SRC_DIR/sapiensmetric-api-update.sh" "$BIN/sapiensmetric-api-update"
install -o root -g root -m 0755 "$SRC_DIR/sapiensmetric-api-role-check.sh" "$BIN/sapiensmetric-api-role-check"
install -o root -g root -m 0644 "$SRC_DIR/verify-api-role.mjs" "$BIN/verify-api-role.mjs"
[[ -f "$SRC_DIR/api-image" ]] || die "missing $SRC_DIR/api-image (the reviewed API image digest)"
install -o root -g root -m 0600 "$SRC_DIR/api-image" /etc/sapiensmetric/api-image
install -d -o root -g root -m 0700 "$CFG_DIR" /opt/sapiensmetric-review/backup /opt/sapiensmetric-review/backup/staging
if [[ ! -f "$CFG_DIR/backup.env" ]]; then
  install -o root -g root -m 0600 "$SRC_DIR/sapiensmetric-backup.env.example" "$CFG_DIR/backup.env"
fi
install -o root -g root -m 0644 "$SRC_DIR/systemd/sapiensmetric-backup.service" /etc/systemd/system/sapiensmetric-backup.service
install -o root -g root -m 0644 "$SRC_DIR/systemd/sapiensmetric-backup.timer" /etc/systemd/system/sapiensmetric-backup.timer
systemctl daemon-reload
log "scripts, config and systemd units installed"

# --- 2. restricted MySQL backup account ------------------------------------
[[ -f "$HOSTENV" ]] || die "hostenv not found: $HOSTENV"
DB_NAME="$(sed -n 's/^MYSQL_DATABASE=//p' "$HOSTENV" | tr -d '"' | head -1)"
[[ -n "$DB_NAME" ]] || die "MYSQL_DATABASE not found in $HOSTENV"
docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER" || die "db container not running: $DB_CONTAINER"

BK_PW="$(openssl rand -base64 36 | tr -d '\n')"
printf '%s' "$BK_PW" >"$SECRETS/sm_backup_password"
chmod 0600 "$SECRETS/sm_backup_password"; chown root:root "$SECRETS/sm_backup_password"
# The password is passed to MySQL on STDIN (never on the command line).
docker exec -i "$DB_CONTAINER" sh -c 'MYSQL_PWD="$(cat /run/secrets/mysql_root_password)" exec mysql -uroot' <<SQL || die "failed to create the backup account"
CREATE USER IF NOT EXISTS 'sapiensmetric_backup'@'%' IDENTIFIED BY '$BK_PW';
ALTER USER 'sapiensmetric_backup'@'%' IDENTIFIED BY '$BK_PW';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'sapiensmetric_backup'@'%';
GRANT SELECT ON \`$DB_NAME\`.* TO 'sapiensmetric_backup'@'%';
FLUSH PRIVILEGES;
SQL
unset BK_PW
log "restricted backup account 'sapiensmetric_backup' (SELECT only on $DB_NAME) ready"

# --- 3. fixed wrappers (no arguments, stripped environment) ----------------
write_wrapper() {
  local name="$1"; shift
  cat >"$BIN/$name" <<WRAP
#!/bin/sh
# Fixed maintenance wrapper (T-023). Takes NO arguments; runs with a stripped
# environment so the caller cannot override paths or config.
exec env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \\
  $*
WRAP
  chown root:root "$BIN/$name"; chmod 0755 "$BIN/$name"
}
write_wrapper sapiensmetric-maint-check          "$BIN/sapiensmetric-backup check-remote"
write_wrapper sapiensmetric-maint-status         "$BIN/sapiensmetric-backup status"
write_wrapper sapiensmetric-maint-backup         "$BIN/sapiensmetric-backup run"
write_wrapper sapiensmetric-maint-restore-verify "$BIN/sapiensmetric-restore-verify run"
write_wrapper sapiensmetric-maint-api-update     "$BIN/sapiensmetric-api-update"
write_wrapper sapiensmetric-maint-api-role-check "$BIN/sapiensmetric-api-role-check"
log "installed fixed wrappers: ${WRAPPERS[*]}"

# --- 4. narrowly scoped sudoers (validated before activation) --------------
ALLOW=""
for w in "${WRAPPERS[@]}"; do ALLOW+="$BIN/$w, "; done
ALLOW="${ALLOW%, }"
TMP_SUDOERS="$(mktemp)"
cat >"$TMP_SUDOERS" <<SUDO
# SapiensMetric scoped maintenance access (T-023). Agent: $AGENT_USER.
# Fixed wrappers only; no shell, no docker, no arbitrary paths/environment.
Defaults:$AGENT_USER !setenv, env_reset, secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
$AGENT_USER ALL=(root) NOPASSWD: $ALLOW
SUDO
chmod 0440 "$TMP_SUDOERS"
visudo -cf "$TMP_SUDOERS" || { rm -f "$TMP_SUDOERS"; die "sudoers validation failed"; }
install -o root -g root -m 0440 "$TMP_SUDOERS" "$SUDOERS_FILE"
rm -f "$TMP_SUDOERS"
log "installed validated sudoers: $SUDOERS_FILE"

# --- 5. enable the timer ----------------------------------------------------
systemctl enable --now sapiensmetric-backup.timer
log "enabled sapiensmetric-backup.timer"

WRAPPER_PATHS=""
for w in "${WRAPPERS[@]}"; do WRAPPER_PATHS+="$BIN/$w "; done

cat <<EOF

Bootstrap complete.

The agent ($AGENT_USER) may now run, without a password, ONLY:
  sudo -n $BIN/sapiensmetric-maint-check
  sudo -n $BIN/sapiensmetric-maint-status
  sudo -n $BIN/sapiensmetric-maint-backup
  sudo -n $BIN/sapiensmetric-maint-restore-verify
  sudo -n $BIN/sapiensmetric-maint-api-update
  sudo -n $BIN/sapiensmetric-maint-api-role-check

Revocation (any time):
  sudo rm -f $SUDOERS_FILE
  sudo rm -f $WRAPPER_PATHS
  (Scheduled backups are NOT disabled by revocation.)
EOF
