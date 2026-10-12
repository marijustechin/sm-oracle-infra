#!/usr/bin/env bash
# sapiensmetric-backup — encrypted off-server backup for the SapiensMetric
# closed-review stack (T-023).
#
# Reuses the EXISTING Sokoladas rclone `crypt` remote (client-side encryption) but
# writes to a SEPARATE remote path (`sapiensmetric-backups/sets`), with its own
# config, staging directory, run lock, log, state and systemd timer. It never
# touches the Sokoladas backup sets, and the Sokoladas PostgreSQL dump does NOT
# cover SapiensMetric (different engine — MySQL). See docs/sapiensmetric-backups.md.
#
# Runs as root from `sapiensmetric-backup.service`. Nothing secret is printed;
# the rclone configuration (OAuth token + crypt password) stays in
# /etc/sokoladas-staging/backup/rclone.conf (root, 0600).
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CONFIG_FILE="${SAPIENSMETRIC_BACKUP_CONFIG:-/etc/sapiensmetric/backup/backup.env}"
# shellcheck source=/dev/null
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

PROJECT="${PROJECT:-sapiensmetric-review}"
DB_CONTAINER="${DB_CONTAINER:-sapiensmetric-review-db-1}"
PROJECT_DIR="${PROJECT_DIR:-/opt/sapiensmetric-review}"
HOSTENV="${HOSTENV:-$PROJECT_DIR/hostenv}"
SECRETS_DIR="${SECRETS_DIR:-/etc/sapiensmetric/secrets}"
INITIAL_DIR="${INITIAL_DIR:-/etc/sapiensmetric/initial-credentials}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/sapiensmetric-review/backup}"
STAGING_DIR="${STAGING_DIR:-/opt/sapiensmetric-review/backup/staging}"
LOG_FILE="${LOG_FILE:-/var/log/sapiensmetric-backup.log}"
RUN_LOCK="${RUN_LOCK:-/run/sapiensmetric-backup.lock}"
RCLONE_BIN="${RCLONE_BIN:-rclone}"
# Reuse the Sokoladas rclone crypt remote config; separate destination path.
RCLONE_CONFIG="${RCLONE_CONFIG:-/etc/sokoladas-staging/backup/rclone.conf}"
REMOTE="${REMOTE:-crypt:}"
SET_PREFIX="${SET_PREFIX:-sapiensmetric-backups/sets}"
KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
MIN_FREE_MB="${MIN_FREE_MB:-2048}"
UPLOAD_RETRIES="${UPLOAD_RETRIES:-3}"
VERIFY_MODE="${VERIFY_MODE:-download}"

if [[ "$(id -u)" -ne 0 ]]; then
  REMOTE="${SAPIENSMETRIC_BACKUP_REMOTE:-$REMOTE}"
  SET_PREFIX="${SAPIENSMETRIC_BACKUP_SET_PREFIX:-$SET_PREFIX}"
  STAGING_DIR="${SAPIENSMETRIC_BACKUP_STAGING_DIR:-$STAGING_DIR}"
  LOG_FILE="${SAPIENSMETRIC_BACKUP_LOG_FILE:-$LOG_FILE}"
  RUN_LOCK="${SAPIENSMETRIC_BACKUP_RUN_LOCK:-$RUN_LOCK}"
  RCLONE_CONFIG="${SAPIENSMETRIC_BACKUP_RCLONE_CONFIG:-$RCLONE_CONFIG}"
fi

die() { log "ERROR: $*"; exit 1; }
log() {
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG_FILE" >&2
}
rclone() { command "$RCLONE_BIN" --config "$RCLONE_CONFIG" "$@"; }

usage() {
  cat >&2 <<'USAGE'
usage: sapiensmetric-backup <command>

  run            create, upload, verify and prune a backup set
  snapshot       create a local set only (no upload)
  status         show configuration readiness and recent state
  check-remote   verify the rclone remote is configured and authorized
  retention      show the retention decision for the remote sets
USAGE
}

require_root() { [[ "$(id -u)" -eq 0 ]] || die "must run as root"; }

# --- retention helper (same policy as the Sokoladas job) -------------------
set_epoch() {
  local name="$1"
  [[ "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}Z$ ]] || return 1
  date -u -d "${name:0:4}-${name:5:2}-${name:8:2} ${name:11:2}:${name:13:2}:${name:15:2}" +%s
}
select_retention() {
  local now_epoch="$1" keep_daily="$2" keep_weekly="$3"
  local name epoch line n e day week
  local -a rows=()
  local -A keep=() seen_dates=() seen_weeks=()
  local dates_seen=0 weeks_seen=0
  while read -r name _; do
    [[ -n "$name" ]] || continue
    epoch="$(set_epoch "$name" 2>/dev/null || true)"
    [[ -n "$epoch" ]] || continue
    rows+=("$name:$epoch")
  done
  [[ "${#rows[@]}" -gt 0 ]] || return 0
  mapfile -t rows < <(printf '%s\n' "${rows[@]}" | sort -t: -k2,2nr)
  for line in "${rows[@]}"; do
    n="${line%%:*}"; e="${line##*:}"
    day="$(date -u -d "@$e" +%F)"; week="$(date -u -d "@$e" +%G-W%V)"
    if [[ -z "${seen_dates[$day]:-}" && "$dates_seen" -lt "$keep_daily" ]]; then
      seen_dates[$day]=1; dates_seen=$((dates_seen + 1)); keep["$n"]=1
    fi
    if [[ -z "${seen_weeks[$week]:-}" && "$weeks_seen" -lt "$keep_weekly" ]]; then
      seen_weeks[$week]=1; weeks_seen=$((weeks_seen + 1)); keep["$n"]=1
    fi
  done
  for line in "${rows[@]}"; do
    n="${line%%:*}"
    if [[ -n "${keep[$n]:-}" ]]; then printf 'keep %s\n' "$n"; else printf 'prune %s\n' "$n"; fi
  done
}

append_state() {
  mkdir -p "$BACKUP_ROOT"
  printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >>"$BACKUP_ROOT/state.log"
}
remote_ready() {
  [[ -f "$RCLONE_CONFIG" ]] || { log "rclone config missing: $RCLONE_CONFIG"; return 2; }
  rclone lsd "$REMOTE" >/dev/null 2>&1 || return 3
  return 0
}
check_free_space() {
  local avail_mb
  avail_mb="$(df -Pm "$STAGING_DIR" 2>/dev/null | awk 'NR==2{print $4}')"
  [[ -n "$avail_mb" ]] || die "cannot determine free space for $STAGING_DIR"
  [[ "$avail_mb" -ge "$MIN_FREE_MB" ]] || die "insufficient free space: ${avail_mb}MB < ${MIN_FREE_MB}MB"
}
acquire_lock() {
  mkdir -p "$(dirname "$RUN_LOCK")"
  exec 7>"$RUN_LOCK"
  flock -n 7 || die "another SapiensMetric backup is already running"
}

# --- snapshot --------------------------------------------------------------
read_hostenv() {
  [[ -f "$HOSTENV" ]] || die "hostenv not found: $HOSTENV"
  # shellcheck disable=SC1090
  set -a; . "$HOSTENV"; set +a
  : "${MYSQL_DATABASE:?hostenv missing MYSQL_DATABASE}"
  : "${MYSQL_USER:?hostenv missing MYSQL_USER}"
}

dump_database() {
  local out="$1"
  docker exec "$DB_CONTAINER" sh -c \
    'exec mysqldump --single-transaction --routines --triggers -u"$MYSQL_USER" -p"$(cat /run/secrets/mysql_password)" "$MYSQL_DATABASE"' \
    | gzip -c >"$out" || die "mysqldump failed"
  [[ -s "$out" ]] || die "mysqldump produced an empty dump"
}

collect_metadata() {
  local out="$1"
  docker exec "$DB_CONTAINER" sh -c \
    'mysql -N -B -u"$MYSQL_USER" -p"$(cat /run/secrets/mysql_password)" "$MYSQL_DATABASE" -e "
       SELECT CONCAT(\"{\\\"users\\\": \", (SELECT COUNT(*) FROM users),
                     \", \\\"assessment_attempts\\\": \", (SELECT COUNT(*) FROM assessment_attempts),
                     \", \\\"migrations\\\": \", (SELECT COUNT(*) FROM migrations), \"}\");"' \
    >"$out" || die "metadata query failed"
  python3 - "$out" <<'PY'
import json, sys
path = sys.argv[1]
open(path, "w").write(json.dumps(json.load(open(path)), indent=2, sort_keys=True) + "\n")
PY
}

do_snapshot() {
  local setdir="$1"
  mkdir -p "$setdir"; chmod 0700 "$setdir"

  log "dumping MySQL database"
  dump_database "$setdir/db.sql.gz"

  log "archiving configuration and host secrets"
  local cfg="$setdir/config"
  mkdir -p "$cfg/etc" "$cfg/state"
  cp -a "$PROJECT_DIR/compose.yaml" "$cfg/compose.yaml"
  cp -a "$PROJECT_DIR/images.env" "$cfg/images.env"
  cp -a "$PROJECT_DIR/hostenv" "$cfg/etc/hostenv"
  [[ -d "$SECRETS_DIR" ]] && cp -a "$SECRETS_DIR" "$cfg/etc/secrets"
  [[ -f "$PROJECT_DIR/SOURCE_COMMIT" ]] && cp -a "$PROJECT_DIR/SOURCE_COMMIT" "$cfg/state/SOURCE_COMMIT"
  tar -C "$cfg" -czf "$setdir/config.tar.gz" . || die "config archive failed"
  rm -rf "$cfg"

  log "collecting metadata"
  collect_metadata "$setdir/metadata.json"

  ( cd "$setdir" && sha256sum db.sql.gz config.tar.gz metadata.json >sha256sums.txt )
  log "snapshot complete: $setdir"
}

verify_upload() {
  local setdir="$1" dest="$2" vdir
  vdir="$(mktemp -d "$STAGING_DIR/.verify.XXXXXX")"
  if ! rclone copy "$dest" "$vdir" --exclude COMPLETE --retries "$UPLOAD_RETRIES" >/dev/null 2>&1; then
    rm -rf "$vdir"; return 1
  fi
  local rc=0
  diff -q "$setdir/sha256sums.txt" "$vdir/sha256sums.txt" >/dev/null 2>&1 || rc=1
  ( cd "$vdir" && sha256sum -c sha256sums.txt ) >/dev/null 2>&1 || rc=1
  rm -rf "$vdir"
  return "$rc"
}
upload_set() {
  local setdir="$1" dest="$2"
  rclone copy "$setdir" "$dest" --exclude COMPLETE --retries "$UPLOAD_RETRIES" || return 1
  if [[ "$VERIFY_MODE" == "download" ]]; then
    verify_upload "$setdir" "$dest" || return 1
  else
    rclone check "$setdir" "$dest" --exclude COMPLETE --size-only --one-way --retries "$UPLOAD_RETRIES" || return 1
  fi
  printf 'complete %s\n' "$(basename "$dest")" >"$setdir/COMPLETE"
  rclone copyto "$setdir/COMPLETE" "$dest/COMPLETE" --retries "$UPLOAD_RETRIES" || return 1
  rclone lsf "$dest" | grep -qx COMPLETE || return 1
}
remote_successful_sets() {
  local set
  while read -r set; do
    [[ -n "$set" ]] || continue
    rclone lsf "$REMOTE/$SET_PREFIX/$set/COMPLETE" >/dev/null 2>&1 && printf '%s\n' "$set"
  done < <(rclone lsf --dirs-only "$REMOTE/$SET_PREFIX" 2>/dev/null | sed 's:/$::')
}
apply_retention() {
  local now_epoch action name
  now_epoch="$(date -u +%s)"
  while read -r action name; do
    [[ -n "$name" ]] || continue
    if [[ ! "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}Z$ ]]; then
      log "skip retention of unexpected name: $name"; continue
    fi
    if [[ "$action" == "prune" ]]; then
      log "pruning old set: $name"
      rclone purge "$REMOTE/$SET_PREFIX/$name" || log "WARN: failed to prune $name"
    fi
  done < <(remote_successful_sets | select_retention "$now_epoch" "$KEEP_DAILY" "$KEEP_WEEKLY")
}

# --- commands --------------------------------------------------------------
cmd_run() {
  require_root
  read_hostenv
  mkdir -p "$BACKUP_ROOT" "$STAGING_DIR"; chmod 0700 "$BACKUP_ROOT" "$STAGING_DIR"
  acquire_lock
  check_free_space
  local rc=0
  remote_ready || rc=$?
  if [[ "$rc" == "3" ]]; then
    append_state NOT_AUTHORIZED "rclone remote not authorized"
    log "backup skipped: rclone remote is not authorized (see docs/backups.md)"
    exit 0
  elif [[ "$rc" != "0" ]]; then
    die "backup remote is not ready (rc=$rc)"
  fi
  local name setdir dest
  name="$(date -u +%Y-%m-%dT%H%M%SZ)"
  setdir="$STAGING_DIR/$name"
  dest="$REMOTE/$SET_PREFIX/$name"
  log "starting SapiensMetric backup set $name"
  do_snapshot "$setdir"
  log "uploading to $dest"
  upload_set "$setdir" "$dest" || die "upload/verification failed; existing remote sets were not touched"
  log "upload verified"
  apply_retention
  rm -rf "$setdir"
  append_state OK "backup $name uploaded and verified"
  log "backup $name complete"
}
cmd_snapshot() { require_root; read_hostenv; mkdir -p "$BACKUP_ROOT" "$STAGING_DIR"; chmod 0700 "$BACKUP_ROOT" "$STAGING_DIR"; acquire_lock; check_free_space; local name setdir; name="$(date -u +%Y-%m-%dT%H%M%SZ)"; setdir="$STAGING_DIR/$name"; do_snapshot "$setdir"; log "snapshot only (not uploaded): $setdir"; }
cmd_status() { echo "rclone: $("$RCLONE_BIN" version 2>/dev/null | head -1 || echo missing)"; echo "config: $RCLONE_CONFIG ($([[ -f "$RCLONE_CONFIG" ]] && echo present || echo missing))"; echo "remote: $REMOTE"; echo "sets:   $SET_PREFIX"; echo "state:"; [[ -f "$BACKUP_ROOT/state.log" ]] && tail -n 10 "$BACKUP_ROOT/state.log" || echo "  (none)"; }
cmd_check_remote() { remote_ready && { echo "remote OK: $REMOTE"; return 0; }; echo "remote NOT ready"; return 1; }
cmd_retention() { remote_successful_sets | select_retention "$(date -u +%s)" "$KEEP_DAILY" "$KEEP_WEEKLY"; }

main() {
  case "${1:-}" in
    run) cmd_run ;;
    snapshot) cmd_snapshot ;;
    status) cmd_status ;;
    check-remote) cmd_check_remote ;;
    retention) cmd_retention ;;
    -h|--help|help|"") usage ;;
    *) usage; die "unknown command: $1" ;;
  esac
}
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi
