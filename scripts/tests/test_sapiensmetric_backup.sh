#!/usr/bin/env bash
# Real execution-path tests for backup/sapiensmetric-backup.sh and
# backup/sapiensmetric-restore-verify.sh.
#
# Requires docker (like the other infra suites). Runs a throwaway MySQL 8.0.46
# on --network none; nothing touches the live databases.
#
# Proves, with a real database:
#   * a SELECT-only restricted account dumps successfully with --no-tablespaces;
#   * a dump privilege failure stops the snapshot (no db.sql.gz, no metadata);
#   * a metadata query failure stops the snapshot (no valid metadata);
#   * an incomplete set is rejected by restore-verify;
#   * a complete set restores into an isolated MySQL and verifies.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
BACKUP_SCRIPT="$REPO_ROOT/backup/sapiensmetric-backup.sh"
RESTORE_SCRIPT="$REPO_ROOT/backup/sapiensmetric-restore-verify.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

command -v docker >/dev/null 2>&1 || { echo "docker not available; skipping"; exit 0; }
command -v openssl >/dev/null 2>&1 || fail "openssl required"

WORK="$(mktemp -d)"
C="sm-backup-test-$$"
ROOTPW="root-$(openssl rand -hex 8)"
RESTRICTED_PW="restricted-$(openssl rand -hex 8)"
cleanup() { docker rm -f "$C" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

echo "starting throwaway MySQL 8.0.46"
docker run -d --name "$C" --network none \
  -e MYSQL_ROOT_PASSWORD="$ROOTPW" -e MYSQL_DATABASE=smtest mysql:8.0.46 >/dev/null \
  || fail "could not start MySQL"

for _ in $(seq 1 60); do
  if docker exec "$C" sh -c "MYSQL_PWD='$ROOTPW' mysql -uroot smtest -e 'SELECT 1'" >/dev/null 2>&1; then break; fi
  sleep 2
done
docker exec "$C" sh -c "MYSQL_PWD='$ROOTPW' mysql -uroot smtest -e 'SELECT 1'" >/dev/null 2>&1 || fail "MySQL not ready"

docker exec -i "$C" sh -c "MYSQL_PWD='$ROOTPW' mysql -uroot smtest" <<'SQL' || fail "schema setup failed"
CREATE TABLE users(id int primary key);
CREATE TABLE assessment_attempts(id int primary key);
CREATE TABLE migrations(id int primary key);
INSERT INTO users VALUES (1),(2),(3);
INSERT INTO assessment_attempts VALUES (1),(2);
INSERT INTO migrations VALUES (1),(2),(3);
SQL

docker exec -i "$C" sh -c "MYSQL_PWD='$ROOTPW' mysql -uroot" <<SQL || fail "user setup failed"
CREATE USER 'sm_backup'@'%' IDENTIFIED BY '$RESTRICTED_PW';
GRANT SELECT ON smtest.* TO 'sm_backup'@'%';
CREATE USER 'sm_nopriv'@'%' IDENTIFIED BY '$RESTRICTED_PW';
FLUSH PRIVILEGES;
SQL

printf '%s' "$RESTRICTED_PW" >"$WORK/pw"; chmod 600 "$WORK/pw"

# --- configure the script's overridable variables --------------------------
# shellcheck source=/dev/null
source "$BACKUP_SCRIPT"
STAGING_DIR="$WORK/staging"; BACKUP_ROOT="$WORK/backup"; LOG_FILE="$WORK/log"
mkdir -p "$STAGING_DIR" "$BACKUP_ROOT"
DB_CONTAINER="$C"; DB_NAME=smtest; BACKUP_DB_USER=sm_backup; BACKUP_PASSWORD_FILE="$WORK/pw"
PROJECT_DIR="$WORK/project"; mkdir -p "$PROJECT_DIR"
printf 'name: test\n' >"$PROJECT_DIR/compose.yaml"
printf 'API_IMAGE=x\n' >"$PROJECT_DIR/images.env"
printf 'MYSQL_DATABASE=smtest\n' >"$PROJECT_DIR/hostenv"
SECRETS_DIR="$WORK/secrets"; mkdir -p "$SECRETS_DIR"

# --- A: restricted SELECT-only account dumps + metadata --------------------
( do_snapshot "$STAGING_DIR/good" ) || fail "snapshot with the restricted account failed"
[[ -s "$STAGING_DIR/good/db.sql.gz" ]] || fail "db.sql.gz missing after a successful snapshot"
[[ -f "$STAGING_DIR/good/sha256sums.txt" ]] || fail "sha256sums.txt missing"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d=={"users":3,"assessment_attempts":2,"migrations":3}, d' "$STAGING_DIR/good/metadata.json" \
  || fail "metadata.json content unexpected"
gzip -t "$STAGING_DIR/good/db.sql.gz" || fail "dump is not valid gzip"
pass "restricted dump + metadata + archive"

# --- B: a dump privilege failure stops the snapshot ------------------------
if ( BACKUP_DB_USER=sm_nopriv do_snapshot "$STAGING_DIR/nopriv" ); then
  fail "snapshot succeeded with a user lacking SELECT (should have failed)"
fi
[[ ! -e "$STAGING_DIR/nopriv/db.sql.gz" ]] || fail "a failed dump left a db.sql.gz"
[[ ! -e "$STAGING_DIR/nopriv/metadata.json" ]] || fail "a failed dump still collected metadata"
pass "dump failure stops publication (no dump, no metadata)"

# --- C: a metadata query failure stops the snapshot ------------------------
if ( DB_NAME=does_not_exist do_snapshot "$STAGING_DIR/nodb" ); then
  fail "snapshot succeeded against a missing database (should have failed)"
fi
[[ ! -e "$STAGING_DIR/nodb/db.sql.gz" ]] || fail "missing-db snapshot left a db.sql.gz"
pass "metadata/query failure stops the snapshot"

# --- D: an incomplete set is rejected by restore-verify --------------------
mkdir -p "$WORK/incomplete"
cp "$STAGING_DIR/good/metadata.json" "$WORK/incomplete/metadata.json"
cp "$STAGING_DIR/good/db.sql.gz" "$WORK/incomplete/db.sql.gz"
if bash "$RESTORE_SCRIPT" verify "$WORK/incomplete" >/dev/null 2>&1; then
  fail "restore-verify accepted a set with no sha256sums.txt"
fi
pass "incomplete set (no checksums) rejected"

# --- E: a complete set restores into an isolated MySQL ---------------------
if ! SAPIENSMETRIC_RESTORE_WORK="$WORK/restore-work" \
     SAPIENSMETRIC_RESTORE_EVIDENCE="$WORK/restore-evidence" \
     bash "$RESTORE_SCRIPT" verify "$STAGING_DIR/good" 2>"$WORK/restore.err"; then
  cat "$WORK/restore.err" >&2
  fail "isolated restore verification failed for a complete set"
fi
pass "complete set restored + verified in isolation"

echo "test_sapiensmetric_backup: OK"
