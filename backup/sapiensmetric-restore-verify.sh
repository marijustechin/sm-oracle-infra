#!/usr/bin/env bash
# sapiensmetric-restore-verify — restore a SapiensMetric backup set into an
# isolated temporary MySQL and verify it against the set's own metadata.
#
# This NEVER touches the live SapiensMetric or Sokoladas databases, volumes or
# networks. It:
#   1. downloads (and decrypts, via the shared rclone `crypt` remote) a set;
#   2. starts a throwaway MySQL 8.0.46 container on `--network none`
#      (no outbound, no published ports);
#   3. loads db.sql.gz into a separate database;
#   4. compares row counts against the set's metadata.json;
#   5. writes a verification report and removes only the throwaway container and
#      temporary directories.
#
# Usage:
#   sapiensmetric-restore-verify run [set-name]     download the newest (or named) set + verify + clean up
#   sapiensmetric-restore-verify verify <local-dir> verify an already-downloaded set
set -euo pipefail

CONFIG_FILE="${SAPIENSMETRIC_BACKUP_CONFIG:-/etc/sapiensmetric/backup/backup.env}"
# shellcheck source=/dev/null
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

RCLONE_BIN="${RCLONE_BIN:-rclone}"
RCLONE_CONFIG="${RCLONE_CONFIG:-/etc/sokoladas-staging/backup/rclone.conf}"
REMOTE="${REMOTE:-crypt:}"
SET_PREFIX="${SET_PREFIX:-sapiensmetric-backups/sets}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/sapiensmetric-review/backup}"
WORK_ROOT="${SAPIENSMETRIC_RESTORE_WORK:-/opt/sapiensmetric-review/backup/restore-work}"
EVIDENCE_ROOT="${SAPIENSMETRIC_RESTORE_EVIDENCE:-/opt/sapiensmetric-review/backup/restore-evidence}"
MYSQL_IMAGE="${MYSQL_IMAGE:-mysql:8.0.46}"
RESTORE_DB="${RESTORE_DB:-sapiensmetric_restore}"

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H%M%SZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
rclone() { command "$RCLONE_BIN" --config "$RCLONE_CONFIG" "$@"; }
require_tools() { command -v docker >/dev/null 2>&1 || die "docker not found"; command -v rclone >/dev/null 2>&1 || die "rclone not found"; }

RESTORE_CONTAINER=""; RESTORE_WORK=""; RESTORE_FETCH=""
cleanup() {
  [[ -n "$RESTORE_CONTAINER" ]] && docker rm -f "$RESTORE_CONTAINER" >/dev/null 2>&1 || true
  [[ -n "$RESTORE_WORK" ]] && rm -rf "$RESTORE_WORK" || true
  [[ -n "$RESTORE_FETCH" ]] && rm -rf "$RESTORE_FETCH" || true
}

latest_set() {
  rclone lsf --dirs-only "$REMOTE/$SET_PREFIX" 2>/dev/null \
    | sed 's:/$::' | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}Z$' | sort | tail -1
}

fetch_set() {
  local name="$1" dest="$WORK_ROOT/$name"
  [[ "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}Z$ ]] || die "invalid set name: $name"
  rm -rf "$dest"; mkdir -p "$dest"
  rclone lsf "$REMOTE/$SET_PREFIX/$name/COMPLETE" >/dev/null 2>&1 || die "set is not complete: $name"
  rclone copy "$REMOTE/$SET_PREFIX/$name" "$dest" --retries 3 --low-level-retries 10 >/dev/null || die "download failed"
  ( cd "$dest" && sha256sum -c sha256sums.txt ) >/dev/null || die "downloaded set failed checksum verification"
  printf '%s' "$dest"
}

verify_set() {
  local setdir="$1" name ts container work evidence
  [[ -f "$setdir/metadata.json" ]] || die "missing metadata.json in $setdir"
  name="$(basename "$setdir")"
  ts="$(date -u +%Y-%m-%dT%H%M%SZ)"
  work="$(mktemp -d "$WORK_ROOT/verify.XXXXXX")"
  evidence="$EVIDENCE_ROOT/$name-$ts"
  mkdir -p "$evidence"
  container="sapiensmetric-restore-verify-$ts"
  RESTORE_CONTAINER="$container"; RESTORE_WORK="$work"

  log "starting isolated MySQL ($MYSQL_IMAGE, --network none)"
  docker run -d --name "$container" --network none \
    -e MYSQL_ROOT_PASSWORD=restore -e MYSQL_DATABASE="$RESTORE_DB" "$MYSQL_IMAGE" >/dev/null
  local i
  for i in $(seq 1 60); do
    docker exec "$container" mysqladmin ping -uroot -prestore --silent >/dev/null 2>&1 && break
    sleep 2
  done
  docker exec "$container" mysqladmin ping -uroot -prestore --silent >/dev/null 2>&1 || die "restore database did not become ready"

  log "restoring db.sql.gz into database $RESTORE_DB"
  gunzip -c "$setdir/db.sql.gz" | docker exec -i "$container" sh -c "exec mysql -uroot -prestore '$RESTORE_DB'" \
    || die "mysql restore failed"

  log "comparing restored counts against the backup metadata"
  docker exec "$container" mysql -N -B -uroot -prestore "$RESTORE_DB" -e \
    'SELECT CONCAT("{\"users\": ", (SELECT COUNT(*) FROM users), ", \"assessment_attempts\": ", (SELECT COUNT(*) FROM assessment_attempts), ", \"migrations\": ", (SELECT COUNT(*) FROM migrations), "}");' \
    >"$work/actual.json"
  if python3 - "$setdir/metadata.json" "$work/actual.json" >"$evidence/metadata-diff.txt" 2>&1 <<'PY'
import json, sys
expected = json.load(open(sys.argv[1]))
actual = json.load(open(sys.argv[2]))
bad = [f"{k}: expected {expected[k]} got {actual.get(k)}"
       for k in expected if actual.get(k) != expected[k]]
for line in bad:
    print(line)
sys.exit(1 if bad else 0)
PY
  then :; else die "restored counts differ from the backup metadata (see $evidence/metadata-diff.txt)"; fi

  {
    echo "set: $name"
    echo "verifiedAt: $ts"
    echo "restoreDatabase: $RESTORE_DB"
    echo "mysqlImage: $MYSQL_IMAGE"
    echo "network: --network none (no outbound, no published ports)"
    echo "liveDatabasesTouched: none"
    echo "result: OK"
  } >"$evidence/report.txt"
  echo "set $name verified; evidence: $evidence"
}

main() {
  trap cleanup EXIT
  case "${1:-}" in
    run)
      require_tools; mkdir -p "$WORK_ROOT" "$EVIDENCE_ROOT"
      local name="${2:-$(latest_set)}"
      [[ -n "$name" ]] || die "no backup sets found at $REMOTE/$SET_PREFIX"
      log "verifying set: $name"
      RESTORE_FETCH="$(fetch_set "$name")"
      verify_set "$RESTORE_FETCH"
      ;;
    verify)
      [[ $# -eq 2 ]] || die "usage: verify <local-dir>"
      require_tools; mkdir -p "$WORK_ROOT" "$EVIDENCE_ROOT"
      verify_set "$2"
      ;;
    *) die "usage: sapiensmetric-restore-verify run [set-name] | verify <local-dir>" ;;
  esac
}
main "$@"
