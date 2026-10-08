#!/usr/bin/env bash
# sokoladas-backup — encrypted off-server backup for the sokoladas-demo stack.
#
# Creates a dated, consistent backup set (PostgreSQL logical dump + uploaded
# media + the configuration needed to reconstruct the deployment, including the
# applied release manifest and host secrets), uploads it through an rclone
# `crypt` remote (encrypted client-side before upload) to Google Drive, verifies
# the upload, and prunes old successful sets by the documented retention policy.
#
# Runs as root from the systemd unit `sokoladas-backup.service`. It coordinates
# with the deployment entry point through the shared deploy lock so a snapshot is
# never taken during a release/migration.
#
# References: docs/backups.md. Nothing secret is printed; the rclone
# configuration (OAuth token + crypt password) stays in
# /etc/sokoladas-staging/backup/rclone.conf (root, 0600) and the recovery bundle.
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

CONFIG_FILE="${SOKOLADAS_BACKUP_CONFIG:-/etc/sokoladas-staging/backup/backup.env}"
# shellcheck source=/dev/null
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

PROJECT="${PROJECT:-sokoladas-staging}"
DB_CONTAINER="${DB_CONTAINER:-sokoladas-staging-db-1}"
DB_NAME="${DB_NAME:-sokoladas_staging}"
DB_SUPERUSER="${DB_SUPERUSER:-postgres}"
DB_ADMIN_PASSWORD_FILE="${DB_ADMIN_PASSWORD_FILE:-/etc/sokoladas-staging/secrets/db_admin_password}"
MEDIA_VOLUME_PATH="${MEDIA_VOLUME_PATH:-/var/lib/docker/volumes/sokoladas-staging_media_data/_data}"
MEDIA_SUBDIR="${MEDIA_SUBDIR:-products}"
SOKOLADAS_ROOT="${SOKOLADAS_ROOT:-/opt/sokoladas-staging}"
DEPLOY_LOCK="${DEPLOY_LOCK:-/opt/sokoladas-staging/state/deploy.lock}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/sokoladas-staging/backup}"
STAGING_DIR="${STAGING_DIR:-/opt/sokoladas-staging/backup/staging}"
LOG_FILE="${LOG_FILE:-/var/log/sokoladas-backup.log}"
RUN_LOCK="${RUN_LOCK:-/run/sokoladas-backup.lock}"
RCLONE_BIN="${RCLONE_BIN:-rclone}"
RCLONE_CONFIG="${RCLONE_CONFIG:-/etc/sokoladas-staging/backup/rclone.conf}"
REMOTE="${REMOTE:-crypt:}"
SET_PREFIX="${SET_PREFIX:-sokoladas-backups/sets}"
KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
MIN_FREE_MB="${MIN_FREE_MB:-2048}"
LOCK_WAIT_SECONDS="${LOCK_WAIT_SECONDS:-900}"
UPLOAD_RETRIES="${UPLOAD_RETRIES:-3}"
VERIFY_MODE="${VERIFY_MODE:-download}"
NOTIFY_TO="${NOTIFY_TO:-}"

# Path overrides are honoured only for a non-root invocation (the deterministic
# tests); the live unit runs as root with the fixed paths above.
if [[ "$(id -u)" -ne 0 ]]; then
  REMOTE="${SOKOLADAS_BACKUP_REMOTE:-$REMOTE}"
  SET_PREFIX="${SOKOLADAS_BACKUP_SET_PREFIX:-$SET_PREFIX}"
  STAGING_DIR="${SOKOLADAS_BACKUP_STAGING_DIR:-$STAGING_DIR}"
  LOG_FILE="${SOKOLADAS_BACKUP_LOG_FILE:-$LOG_FILE}"
  RUN_LOCK="${SOKOLADAS_BACKUP_RUN_LOCK:-$RUN_LOCK}"
  RCLONE_CONFIG="${SOKOLADAS_BACKUP_RCLONE_CONFIG:-$RCLONE_CONFIG}"
fi

die() { log "ERROR: $*"; exit 1; }
log() {
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG_FILE" >&2
}
rclone() { command "$RCLONE_BIN" --config "$RCLONE_CONFIG" "$@"; }

usage() {
  cat >&2 <<'USAGE'
usage: sokoladas-backup <command>

  run              create, upload, verify and prune a backup set
  snapshot         create and verify a local set only (no upload)
  status           show configuration readiness and recent state
  check-remote     verify the rclone remote is configured and authorized
  retention        show the retention decision for the remote sets
  resolve-folder   resolve and pin the Drive destination folder id
  set-token        install the Google OAuth token from stdin into rclone.conf
USAGE
}

require_root() { [[ "$(id -u)" -eq 0 ]] || die "must run as root"; }

# ---------------------------------------------------------------------------
# Pure helpers (unit-tested in scripts/tests/test_backup.sh)
# ---------------------------------------------------------------------------

# set_epoch <YYYY-MM-DDTHHMMSSZ> -> UTC epoch seconds, or non-zero if malformed.
set_epoch() {
  local name="$1"
  [[ "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}Z$ ]] || return 1
  date -u -d "${name:0:4}-${name:5:2}-${name:8:2} ${name:11:2}:${name:13:2}:${name:15:2}" +%s
}

# select_retention <now-epoch> <keep_daily> <keep_weekly>
# Reads successful set names on stdin and prints "keep <name>" / "prune <name>":
# keep the newest set of each of the most recent <keep_daily> UTC days and the
# newest set of each of the most recent <keep_weekly> ISO weeks; prune the rest.
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
    day="$(date -u -d "@$e" +%F)"
    week="$(date -u -d "@$e" +%G-W%V)"
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

# verify_media_refs <tar-listing-file>
# Reads referenced media paths (/media/products/x.webp) on stdin and fails if any
# is not present in the archive.
verify_media_refs() {
  python3 -c '
import sys
listing = set()
with open(sys.argv[1], encoding="utf-8", errors="replace") as handle:
    for line in handle:
        listing.add(line.strip().lstrip("./"))
missing = []
for line in sys.stdin:
    ref = line.strip()
    if not ref:
        continue
    key = ref[len("/media/"):] if ref.startswith("/media/") else ref
    if key not in listing:
        missing.append(ref)
if missing:
    print("missing referenced media: " + ", ".join(missing), file=sys.stderr)
    sys.exit(1)
' "$1"
}

# compare_metadata <expected.json> <actual.json>
# Fails when a recorded count differs between the backup and the restore.
compare_metadata() {
  python3 - "$1" "$2" <<'PY'
import json, sys
expected = json.load(open(sys.argv[1]))
actual = json.load(open(sys.argv[2]))
skip = {"schemaVersion", "createdAt", "releaseId", "source", "images", "sha256",
        "sizes", "files", "application"}
bad = [f"{k}: expected {expected[k]} got {actual.get(k)}"
       for k in expected if k not in skip and actual.get(k) != expected[k]]
for line in bad:
    print(line)
sys.exit(1 if bad else 0)
PY
}

# ---------------------------------------------------------------------------
# Runtime helpers
# ---------------------------------------------------------------------------

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
  log "free space OK: ${avail_mb}MB"
}

acquire_locks() {
  mkdir -p "$(dirname "$RUN_LOCK")" "$(dirname "$DEPLOY_LOCK")"
  exec 8>"$DEPLOY_LOCK"
  flock -s -w "$LOCK_WAIT_SECONDS" 8 || die "timed out waiting for the deploy lock (release in progress?)"
  exec 7>"$RUN_LOCK"
  flock -n 7 || die "another backup is already running"
}

# ---------------------------------------------------------------------------
# Snapshot
# ---------------------------------------------------------------------------

dump_database() {
  local out="$1"
  docker exec "$DB_CONTAINER" sh -c \
    'PGPASSWORD="$(cat /run/secrets/db_admin_password)" exec pg_dump -U "$0" -Fc -d "$1"' \
    "$DB_SUPERUSER" "$DB_NAME" >"$out" || die "pg_dump failed"
  [[ -s "$out" ]] || die "pg_dump produced an empty dump"
}

psql_json() {
  docker exec "$DB_CONTAINER" psql -U "$DB_SUPERUSER" -d "$DB_NAME" -tAc "$1"
}

collect_metadata() {
  local out="$1"
  psql_json "select json_build_object(
    'users', (select count(*) from users),
    'auth_accounts', (select count(*) from auth_accounts),
    'categories', (select count(*) from categories),
    'catalog_products', (select count(*) from catalog_products),
    'catalog_tags', (select count(*) from catalog_tags),
    'shop_products', (select count(*) from shop_products),
    'product_tag_links', (select count(*) from \"_CatalogProductToCatalogTag\"),
    'products_with_rating', (select count(*) from catalog_products where \"ratingCount\" is not null and \"ratingCount\" > 0),
    'media_referenced', (select count(distinct \"primaryImageUrl\") from catalog_products where \"primaryImageUrl\" like '/media/products/%'))" \
    >"$out" || die "metadata query failed"
  python3 - "$out" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
if not isinstance(data, dict):
    print("metadata query did not return an object", file=sys.stderr); sys.exit(1)
json.dump(data, open(path, "w"), indent=2, sort_keys=True)
open(path, "a").write("\n")
PY
}

referenced_media() {
  psql_json "select \"primaryImageUrl\" from catalog_products where \"primaryImageUrl\" like '/media/products/%'
             union select \"primaryImageUrl\" from shop_products where \"primaryImageUrl\" like '/media/products/%'" \
    | sed -n 's/^[[:space:]]*//; /^$/d; p'
}

do_snapshot() {
  local setdir="$1"
  mkdir -p "$setdir"; chmod 0700 "$setdir"

  log "dumping database ($DB_NAME)"
  dump_database "$setdir/db.dump"

  log "archiving media ($MEDIA_VOLUME_PATH/$MEDIA_SUBDIR)"
  if [[ -d "$MEDIA_VOLUME_PATH/$MEDIA_SUBDIR" ]]; then
    tar -C "$MEDIA_VOLUME_PATH" -czf "$setdir/media.tar.gz" "$MEDIA_SUBDIR" || die "media archive failed"
  else
    tar -C "$MEDIA_VOLUME_PATH" -czf "$setdir/media.tar.gz" --files-from /dev/null || die "empty media archive failed"
  fi

  log "archiving configuration and host secrets"
  local cfg="$setdir/config"
  mkdir -p "$cfg/etc" "$cfg/state"
  cp -a /etc/sokoladas-staging/hostenv "$cfg/etc/hostenv"
  cp -a /etc/sokoladas-staging/secrets "$cfg/etc/secrets"
  cp -a "$SOKOLADAS_ROOT/state/applied.json" "$cfg/state/applied.json"
  [[ -f "$SOKOLADAS_ROOT/template/VERSION" ]] && cp -a "$SOKOLADAS_ROOT/template/VERSION" "$cfg/template-VERSION"
  local release_id
  release_id="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["releaseId"])' "$SOKOLADAS_ROOT/state/applied.json")"
  cp -a "$SOKOLADAS_ROOT/releases/$release_id/releases/$release_id.json" "$cfg/release-manifest.json"
  cp -a "$SOKOLADAS_ROOT/releases/$release_id/compose.yaml" "$cfg/compose.yaml"
  tar -C "$cfg" -czf "$setdir/config.tar.gz" . || die "config archive failed"
  rm -rf "$cfg"

  log "collecting metadata"
  collect_metadata "$setdir/metadata.json"

  log "verifying referenced media are present in the archive"
  tar -tzf "$setdir/media.tar.gz" >"$setdir/.media.list"
  referenced_media | sort -u >"$setdir/.media.refs"
  if ! verify_media_refs "$setdir/.media.list" <"$setdir/.media.refs"; then
    rm -f "$setdir/.media.list" "$setdir/.media.refs"
    die "media archive is missing files referenced by the database snapshot"
  fi
  rm -f "$setdir/.media.list" "$setdir/.media.refs"

  log "hashing artifacts"
  ( cd "$setdir" && sha256sum db.dump media.tar.gz config.tar.gz >sha256sums.txt )

  python3 - "$setdir" "$release_id" "$SOKOLADAS_ROOT/state/applied.json" <<'PY'
import json, os, sys
setdir, release_id, applied = sys.argv[1:4]
meta = json.load(open(os.path.join(setdir, "metadata.json")))
state = json.load(open(applied))
meta["application"] = {
    "releaseId": release_id,
    "sourceCommit": state.get("source", {}).get("commit"),
    "webImage": state.get("images", {}).get("web"),
    "apiImage": state.get("images", {}).get("api"),
}
meta["files"] = {f: os.path.getsize(os.path.join(setdir, f))
                 for f in ("db.dump", "media.tar.gz", "config.tar.gz")}
json.dump(meta, open(os.path.join(setdir, "metadata.json"), "w"), indent=2, sort_keys=True)
open(os.path.join(setdir, "metadata.json"), "a").write("\n")
PY

  log "snapshot complete: $setdir"
}

# ---------------------------------------------------------------------------
# Upload / verify / retention
# ---------------------------------------------------------------------------

verify_upload() {
  local setdir="$1" dest="$2" vdir
  vdir="$(mktemp -d "$STAGING_DIR/.verify.XXXXXX")"
  if ! rclone copy "$dest" "$vdir" --exclude COMPLETE --retries "$UPLOAD_RETRIES" --low-level-retries 10 >/dev/null 2>&1; then
    rm -rf "$vdir"; return 1
  fi
  local ok=0
  diff -q "$setdir/sha256sums.txt" "$vdir/sha256sums.txt" >/dev/null 2>&1 || ok=1
  ( cd "$vdir" && sha256sum -c sha256sums.txt ) >/dev/null 2>&1 || ok=1
  rm -rf "$vdir"
  return "$ok"
}

upload_set() {
  local setdir="$1" dest="$2"
  rclone copy "$setdir" "$dest" --exclude COMPLETE \
    --retries "$UPLOAD_RETRIES" --low-level-retries 10 || return 1
  if [[ "$VERIFY_MODE" == "download" ]]; then
    verify_upload "$setdir" "$dest" || return 1
  else
    rclone check "$setdir" "$dest" --exclude COMPLETE --size-only --one-way \
      --retries "$UPLOAD_RETRIES" || return 1
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

# ---------------------------------------------------------------------------
# Failure notification (best effort, existing Resend channel)
# ---------------------------------------------------------------------------

notify_failure() {
  local message="$1"
  [[ -n "$NOTIFY_TO" ]] || { log "no NOTIFY_TO configured; failure not emailed"; return 0; }
  local key from from_addr
  key="$(cat /etc/sokoladas-staging/secrets/smtp_password 2>/dev/null || true)"
  from="$(sed -n 's/^MAIL_FROM=//p' /etc/sokoladas-staging/hostenv/smtp.env 2>/dev/null | tr -d '"')"
  [[ -n "$key" && -n "$from" ]] || { log "cannot notify (no smtp secret or MAIL_FROM)"; return 0; }
  from_addr="${from##*<}"; from_addr="${from_addr%%>*}"
  if curl -sS --max-time 30 -X POST https://api.resend.com/emails \
    -H "Authorization: Bearer $key" -H 'Content-Type: application/json' \
    -d "$(python3 -c 'import json,sys;print(json.dumps({"from":sys.argv[2],"to":[sys.argv[1]],"subject":"sokoladas backup FAILED","text":sys.argv[3]}))' "$NOTIFY_TO" "$from" "$message")" \
    >/dev/null 2>&1; then
    log "failure notification sent"
  else
    log "WARN: failure notification could not be sent"
  fi
}

_backup_exit() {
  local code=$?
  if [[ "$code" -ne 0 && "${_BACKUP_SUCCESS:-0}" != "1" ]]; then
    append_state FAIL "backup exited $code"
    notify_failure "sokoladas-demo backup failed (exit $code) at $(date -u +%Y-%m-%dT%H:%M:%SZ). No old backups were removed."
  fi
  return "$code"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_run() {
  require_root
  mkdir -p "$BACKUP_ROOT" "$STAGING_DIR"; chmod 0700 "$BACKUP_ROOT" "$STAGING_DIR"
  trap _backup_exit EXIT
  acquire_locks
  check_free_space

  local rc=0
  remote_ready || rc=$?
  if [[ "$rc" == "3" ]]; then
    append_state NOT_AUTHORIZED "Google Drive remote not authorized; see docs/backups.md"
    log "backup skipped: Google Drive remote is not authorized yet"
    _BACKUP_SUCCESS=1; exit 0
  elif [[ "$rc" != "0" ]]; then
    die "backup remote is not ready (rc=$rc)"
  fi

  local name setdir dest
  name="$(date -u +%Y-%m-%dT%H%M%SZ)"
  setdir="$STAGING_DIR/$name"
  dest="$REMOTE/$SET_PREFIX/$name"

  log "starting backup set $name"
  do_snapshot "$setdir"
  log "uploading to $dest"
  upload_set "$setdir" "$dest" || die "upload/verification failed; existing remote sets were not touched"
  log "upload verified"
  log "applying retention (daily=$KEEP_DAILY weekly=$KEEP_WEEKLY)"
  apply_retention

  rm -rf "$setdir"
  append_state OK "backup $name uploaded and verified"
  log "backup $name complete"
  _BACKUP_SUCCESS=1
}

cmd_snapshot() {
  require_root
  mkdir -p "$BACKUP_ROOT" "$STAGING_DIR"; chmod 0700 "$BACKUP_ROOT" "$STAGING_DIR"
  acquire_locks
  check_free_space
  local name setdir
  name="$(date -u +%Y-%m-%dT%H%M%SZ)"
  setdir="$STAGING_DIR/$name"
  do_snapshot "$setdir"
  log "snapshot only (not uploaded): $setdir"
}

cmd_status() {
  echo "rclone:  $("$RCLONE_BIN" version 2>/dev/null | head -1 || echo missing)"
  echo "config:  $RCLONE_CONFIG ($([[ -f "$RCLONE_CONFIG" ]] && echo present || echo missing))"
  echo "remote:  $REMOTE"
  echo "sets:    $SET_PREFIX"
  echo "state:"
  if [[ -f "$BACKUP_ROOT/state.log" ]]; then tail -n 10 "$BACKUP_ROOT/state.log"; else echo "  (none)"; fi
}

cmd_check_remote() { remote_ready && { echo "remote OK: $REMOTE"; return 0; }; echo "remote NOT ready"; return 1; }
cmd_retention() { remote_successful_sets | select_retention "$(date -u +%s)" "$KEEP_DAILY" "$KEEP_WEEKLY"; }

cmd_set_token() {
  require_root
  local token
  token="$(cat)"
  [[ -n "$token" ]] || die "no token on stdin"
  python3 - "$RCLONE_CONFIG" "$token" <<'PY'
import json, sys
path, token = sys.argv[1], sys.argv[2]
try:
    json.loads(token)
except Exception as e:
    print(f"token is not valid JSON: {e}", file=sys.stderr); sys.exit(1)
lines = open(path).read().splitlines()
out, section, replaced = [], None, False
for line in lines:
    if line.startswith('['):
        section = line.strip('[]')
    if section == 'gdrive' and line.startswith('token'):
        out.append('token = ' + token); replaced = True
    else:
        out.append(line)
if not replaced:
    out.append('token = ' + token)
open(path, 'w').write('\n'.join(out) + '\n')
PY
  chmod 0600 "$RCLONE_CONFIG"
  log "token installed"
}

cmd_resolve_folder() {
  require_root
  local parent name json id
  parent="${FOLDER_PARENT:-atsargines-kopijos}"
  name="${FOLDER_NAME:-sokoladas}"
  json="$(rclone lsjson "gdrive:$parent" 2>/dev/null)" || die "cannot list gdrive:$parent (authorized?)"
  id="$(python3 - "$json" "$name" <<'PY'
import json, sys
entries = json.loads(sys.argv[1]); wanted = sys.argv[2]
matches = [e for e in entries if e.get("Name") == wanted and e.get("IsDir")]
if len(matches) != 1:
    print(f"expected exactly one folder named {wanted!r}, found {len(matches)}", file=sys.stderr)
    sys.exit(1)
print(matches[0]["ID"])
PY
)" || die "destination folder identity is ambiguous; refusing to guess"
  python3 - "$RCLONE_CONFIG" "$id" <<'PY'
import sys
path, fid = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines()
out, section, replaced = [], None, False
for line in lines:
    if line.startswith('['):
        section = line.strip('[]')
    if section == 'gdrive' and line.startswith('root_folder_id'):
        out.append('root_folder_id = ' + fid); replaced = True
    else:
        out.append(line)
if not replaced:
    idx = [i for i, l in enumerate(out) if l.strip() == '[gdrive]'][0] + 1
    out.insert(idx, 'root_folder_id = ' + fid)
open(path, 'w').write('\n'.join(out) + '\n')
PY
  log "destination folder id pinned"
}

main() {
  case "${1:-}" in
    run) cmd_run ;;
    snapshot) cmd_snapshot ;;
    status) cmd_status ;;
    check-remote) cmd_check_remote ;;
    retention) cmd_retention ;;
    set-token) cmd_set_token ;;
    resolve-folder) cmd_resolve_folder ;;
    -h|--help|help|"") usage ;;
    *) usage; die "unknown command: $1" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
