#!/usr/bin/env bash
# sokoladas-restore-verify — restore a backup set into an isolated environment
# and verify it against the backup's own recorded snapshot.
#
# This never touches the live database or media volume. It:
#   1. downloads (and decrypts, via the rclone `crypt` remote) a chosen set;
#   2. starts a throwaway PostgreSQL container on an isolated `--network none`
#      (no outbound email or external integrations, no published ports);
#   3. restores the logical dump into a separate database;
#   4. extracts the media archive separately;
#   5. compares row counts and referenced media against the set's metadata.json;
#   6. writes a verification report and removes only the throwaway container and
#      temporary extraction dirs.
#
# Usage:
#   sokoladas-restore-verify run <set-name>      download + verify + cleanup
#   sokoladas-restore-verify verify <local-dir>  verify an already-downloaded set
#
# References: docs/backups.md.
set -euo pipefail

CONFIG_FILE="${SOKOLADAS_BACKUP_CONFIG:-/etc/sokoladas-staging/backup/backup.env}"
# shellcheck source=/dev/null
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

RCLONE_BIN="${RCLONE_BIN:-rclone}"
RCLONE_CONFIG="${RCLONE_CONFIG:-/etc/sokoladas-staging/backup/rclone.conf}"
REMOTE="${REMOTE:-crypt:}"
SET_PREFIX="${SET_PREFIX:-sokoladas-backups/sets}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/sokoladas-staging/backup}"
WORK_ROOT="${SOKOLADAS_RESTORE_WORK:-/opt/sokoladas-staging/backup/restore-work}"
EVIDENCE_ROOT="${SOKOLADAS_RESTORE_EVIDENCE:-/opt/sokoladas-staging/backup/restore-evidence}"
PG_IMAGE="${PG_IMAGE:-postgres@sha256:4ef4dbc939d61acea57712655ddb4b4ab27419c913f94cca0cd57cb3ea3c2280}"
RESTORE_DB="${RESTORE_DB:-sokoladas_restore}"

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
rclone() { command "$RCLONE_BIN" --config "$RCLONE_CONFIG" "$@"; }

# Cleanup state is global so the EXIT trap remains valid after verify_set returns.
RESTORE_CONTAINER=""
RESTORE_WORK=""
cleanup() {
  [[ -n "$RESTORE_CONTAINER" ]] && docker rm -f "$RESTORE_CONTAINER" >/dev/null 2>&1 || true
  [[ -n "$RESTORE_WORK" ]] && rm -rf "$RESTORE_WORK" || true
}

COUNTS_SQL="select json_build_object(
  'users', (select count(*) from users),
  'auth_accounts', (select count(*) from auth_accounts),
  'categories', (select count(*) from categories),
  'catalog_products', (select count(*) from catalog_products),
  'catalog_tags', (select count(*) from catalog_tags),
  'shop_products', (select count(*) from shop_products),
  'product_tag_links', (select count(*) from \"_CatalogProductToCatalogTag\"),
  'products_with_rating', (select count(*) from catalog_products where \"ratingCount\" is not null and \"ratingCount\" > 0),
  'media_referenced', (select count(distinct \"primaryImageUrl\") from catalog_products where \"primaryImageUrl\" like '/media/products/%'))"

fetch_set() {
  local name="$1" dest="$WORK_ROOT/$name"
  rm -rf "$dest"; mkdir -p "$dest"
  [[ "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}Z$ ]] || die "invalid set name: $name"
  rclone lsf "$REMOTE/$SET_PREFIX/$name/COMPLETE" >/dev/null 2>&1 || die "set is not complete: $name"
  rclone copy "$REMOTE/$SET_PREFIX/$name" "$dest" --retries 3 --low-level-retries 10 >/dev/null || die "download failed"
  ( cd "$dest" && sha256sum -c sha256sums.txt ) >/dev/null || die "downloaded set failed checksum verification"
  printf '%s' "$dest"
}

verify_set() {
  local setdir="$1" name ts container work evidence media_dir report
  [[ -f "$setdir/metadata.json" ]] || die "missing metadata.json in $setdir"
  name="$(basename "$setdir")"
  ts="$(date -u +%Y-%m-%dT%H%M%SZ)"
  work="$(mktemp -d "$WORK_ROOT/verify.XXXXXX")"
  media_dir="$work/media"
  mkdir -p "$media_dir" "$EVIDENCE_ROOT/$name-$ts"
  evidence="$EVIDENCE_ROOT/$name-$ts"
  container="sokoladas-restore-verify-$ts"
  RESTORE_CONTAINER="$container"
  RESTORE_WORK="$work"

  log "starting isolated PostgreSQL ($PG_IMAGE, --network none)"
  docker run -d --name "$container" --network none \
    -e POSTGRES_PASSWORD=restore -e POSTGRES_DB="$RESTORE_DB" \
    -e POSTGRES_HOST_AUTH_METHOD=trust "$PG_IMAGE" >/dev/null
  local i
  for i in $(seq 1 30); do
    docker exec "$container" pg_isready -U postgres -d "$RESTORE_DB" >/dev/null 2>&1 && break
    sleep 1
  done
  docker exec "$container" pg_isready -U postgres -d "$RESTORE_DB" >/dev/null 2>&1 || die "restore database did not become ready"

  log "restoring dump into database $RESTORE_DB"
  docker exec -i "$container" pg_restore -U postgres -d "$RESTORE_DB" --no-owner --no-privileges --exit-on-error \
    <"$setdir/db.dump" || die "pg_restore failed"

  log "extracting media"
  tar -xzf "$setdir/media.tar.gz" -C "$media_dir" || die "media extraction failed"

  log "comparing restored counts against the backup snapshot"
  docker exec "$container" psql -U postgres -d "$RESTORE_DB" -tAc "$COUNTS_SQL" >"$work/actual.json"
  if python3 - "$setdir/metadata.json" "$work/actual.json" >"$evidence/metadata-diff.txt" 2>&1 <<'PY'
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
  then
    :
  else
    die "restored counts differ from the backup metadata (see $evidence/metadata-diff.txt)"
  fi

  log "verifying referenced media exist in the extracted archive"
  docker exec "$container" psql -U postgres -d "$RESTORE_DB" -tAc \
    "select \"primaryImageUrl\" from catalog_products where \"primaryImageUrl\" like '/media/products/%' union select \"primaryImageUrl\" from shop_products where \"primaryImageUrl\" like '/media/products/%'" \
    | sed -n 's/^[[:space:]]*//; /^$/d; p' >"$work/refs.txt"

  local missing=0
  while read -r ref; do
    [[ -n "$ref" ]] || continue
    [[ -f "$media_dir/${ref#/media/}" ]] || { echo "MISSING $ref" >>"$evidence/media-missing.txt"; missing=1; }
  done <"$work/refs.txt"
  [[ "$missing" -eq 0 ]] || die "media archive is missing referenced files (see $evidence/media-missing.txt)"

  log "recording recovery facts"
  {
    echo "set: $name"
    echo "verifiedAt: $ts"
    echo "restoreDatabase: $RESTORE_DB"
    echo "postgresImage: $PG_IMAGE"
    echo "rolesInRestoredObjects: pg_restore --no-owner --no-privileges"
    echo "extensions: (plpgsql only; see pg_extension in the restored DB)"
    echo "network: --network none (no outbound email / external integrations)"
    echo "result: OK"
  } >"$evidence/report.txt"
  echo "set $name verified; evidence: $evidence"
}

main() {
  trap cleanup EXIT
  case "${1:-}" in
    run)
      [[ $# -eq 2 ]] || die "usage: run <set-name>"
      require_tools; mkdir -p "$WORK_ROOT" "$EVIDENCE_ROOT"
      local dir; dir="$(fetch_set "$2")"
      verify_set "$dir"
      ;;
    verify)
      [[ $# -eq 2 ]] || die "usage: verify <local-dir>"
      require_tools; mkdir -p "$WORK_ROOT" "$EVIDENCE_ROOT"
      verify_set "$2"
      ;;
    *) die "usage: sokoladas-restore-verify run <set-name> | verify <local-dir>" ;;
  esac
}

require_tools() {
  command -v docker >/dev/null 2>&1 || die "docker not found"
  command -v rclone >/dev/null 2>&1 || die "rclone not found"
}

main "$@"
