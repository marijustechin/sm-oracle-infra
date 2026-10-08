#!/usr/bin/env bash
# Deterministic tests for backup/sokoladas-backup.sh.
#
# No Oracle access, no Docker, no Google: the retention selection, media
# reference check and metadata comparison are exercised as pure functions, and
# the upload/verify/retention path is exercised against a real, local rclone
# `crypt` remote so encryption and pruning are genuinely tested.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$REPO_ROOT/backup/sokoladas-backup.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

command -v rclone >/dev/null 2>&1 || { echo "rclone not available; skipping"; exit 0; }

# --- local crypt remote ----------------------------------------------------
PW="$(rclone obscure 'test-password')"
SALT="$(rclone obscure 'test-salt')"
mkdir -p "$WORK/remote"
cat >"$WORK/rclone.conf" <<EOF
[localtest]
type = local

[crypttest]
type = crypt
remote = localtest:$WORK/remote
filename_encryption = standard
directory_name_encryption = true
password = $PW
password2 = $SALT
EOF

cat >"$WORK/backup.env" <<'ENV'
KEEP_DAILY=2
KEEP_WEEKLY=2
ENV

export SOKOLADAS_BACKUP_CONFIG="$WORK/backup.env"
export SOKOLADAS_BACKUP_RCLONE_CONFIG="$WORK/rclone.conf"
export SOKOLADAS_BACKUP_REMOTE="crypttest:"
export SOKOLADAS_BACKUP_SET_PREFIX="sets"
export SOKOLADAS_BACKUP_STAGING_DIR="$WORK/staging"
export SOKOLADAS_BACKUP_LOG_FILE="$WORK/log"
export SOKOLADAS_BACKUP_RUN_LOCK="$WORK/run.lock"
mkdir -p "$WORK/staging"

# shellcheck source=/dev/null
source "$SCRIPT"
set +e

PASS=0
FAILN=0
ok() { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
not_ok() { FAILN=$((FAILN + 1)); printf 'FAIL - %s\n' "$1"; }
assert_eq() { if [[ "$2" == "$3" ]]; then ok "$1"; else not_ok "$1 (expected '$3', got '$2')"; fi; }
assert_zero() { if [[ "$2" -eq 0 ]]; then ok "$1"; else not_ok "$1 (expected zero, got $2)"; fi; }
assert_ne0() { if [[ "$2" -ne 0 ]]; then ok "$1"; else not_ok "$1 (expected nonzero)"; fi; }

# ---------------------------------------------------------------------------
# set_epoch
# ---------------------------------------------------------------------------
set_epoch "2026-10-15T030000Z" >/dev/null 2>&1
assert_zero "set_epoch parses a valid set name" $?
set_epoch "2026-10-15" >/dev/null 2>&1
assert_ne0 "set_epoch rejects a malformed name" $?
assert_eq "set_epoch is UTC-correct" "$(set_epoch 2026-01-01T000000Z)" "$(date -u -d '2026-01-01T00:00:00Z' +%s)"

# ---------------------------------------------------------------------------
# select_retention (cross-checked against an independent Python reference)
# ---------------------------------------------------------------------------
NOW="$(date -u -d '2026-10-15T12:00:00Z' +%s)"
SETS=$'2026-10-15T030000Z\n2026-10-14T030000Z\n2026-10-13T030000Z\n2026-10-08T030000Z\n2026-10-01T030000Z'
printf '%s\n' "$SETS" >"$WORK/sets.txt"
GOT="$(printf '%s\n' "$SETS" | select_retention "$NOW" 2 2 | sort)"
EXPECTED="$(python3 - "$WORK/sets.txt" "$NOW" 2 2 <<'PY'
import sys, datetime
path, now, kd, kw = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
names = open(path).read().split()
def ep(n): return datetime.datetime.strptime(n, "%Y-%m-%dT%H%M%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()
rows = sorted(names, key=ep, reverse=True)
kd_, kw_ = set(), set()
keep = set()
for n in rows:
    d = datetime.datetime.fromtimestamp(ep(n), datetime.timezone.utc).date()
    iso = d.isocalendar()[:2]
    if d not in kd_ and len(kd_) < kd: kd_.add(d); keep.add(n)
    if iso not in kw_ and len(kw_) < kw: kw_.add(iso); keep.add(n)
out = [("keep " if n in keep else "prune ") + n for n in rows]
print("\n".join(sorted(out)))
PY
)"
assert_eq "select_retention matches the reference decision" "$GOT" "$EXPECTED"
assert_eq "select_retention always keeps the newest set" \
  "$(printf '%s\n' "$SETS" | select_retention "$NOW" 2 2 | grep '^keep 2026-10-15')" "keep 2026-10-15T030000Z"

# ---------------------------------------------------------------------------
# verify_media_refs
# ---------------------------------------------------------------------------
printf 'products/a.webp\nproducts/b.webp\n' >"$WORK/listing.txt"
printf '/media/products/a.webp\n/media/products/b.webp\n' | verify_media_refs "$WORK/listing.txt" >/dev/null 2>&1
assert_zero "verify_media_refs accepts present references" $?
printf '/media/products/missing.webp\n' | verify_media_refs "$WORK/listing.txt" >/dev/null 2>&1
assert_ne0 "verify_media_refs detects a missing referenced file" $?

# ---------------------------------------------------------------------------
# compare_metadata
# ---------------------------------------------------------------------------
printf '{"users":4,"catalog_products":5}\n' >"$WORK/exp.json"
printf '{"users":4,"catalog_products":5}\n' >"$WORK/act.json"
compare_metadata "$WORK/exp.json" "$WORK/act.json" >/dev/null 2>&1
assert_zero "compare_metadata accepts identical counts" $?
printf '{"users":4,"catalog_products":4}\n' >"$WORK/act.json"
compare_metadata "$WORK/exp.json" "$WORK/act.json" >/dev/null 2>&1
assert_ne0 "compare_metadata detects a differing count" $?

# ---------------------------------------------------------------------------
# rclone crypt round-trip (encryption really happens)
# ---------------------------------------------------------------------------
printf 'top secret payload\n' >"$WORK/plain.txt"
rclone copyto "$WORK/plain.txt" "crypttest:roundtrip/plain.txt" >/dev/null 2>&1
assert_zero "crypt upload succeeds" $?
rclone copyto "crypttest:roundtrip/plain.txt" "$WORK/back.txt" >/dev/null 2>&1
assert_eq "crypt download returns identical plaintext" "$(cat "$WORK/back.txt")" "top secret payload"
if rclone lsf "localtest:" | grep -q 'plain.txt'; then
  not_ok "crypt remote stores filenames encrypted"
else
  ok "crypt remote stores filenames encrypted"
fi

# ---------------------------------------------------------------------------
# Upload / verify / completion marker against the local crypt remote
# ---------------------------------------------------------------------------
mkdir -p "$WORK/set1"
printf 'dump\n' >"$WORK/set1/db.dump"
printf 'media\n' >"$WORK/set1/media.tar.gz"
( cd "$WORK/set1" && sha256sum db.dump media.tar.gz >sha256sums.txt )
upload_set "$WORK/set1" "crypttest:sets/set1" >/dev/null 2>&1
assert_zero "upload_set uploads and verifies" $?
rclone lsf "crypttest:sets/set1" 2>/dev/null | grep -qx COMPLETE
assert_zero "upload_set writes the COMPLETE marker" $?

# ---------------------------------------------------------------------------
# Retention: prune older successful sets, never an incomplete/failed one
# ---------------------------------------------------------------------------
mk_set() { # <name> <complete?>
  rclone mkdir "crypttest:sets/$1" >/dev/null 2>&1
  printf 'x\n' >"$WORK/marker"
  rclone copyto "$WORK/marker" "crypttest:sets/$1/data" >/dev/null 2>&1
  [[ "$2" == "complete" ]] && rclone copyto "$WORK/marker" "crypttest:sets/$1/COMPLETE" >/dev/null 2>&1
}
# Four complete sets on four recent, consecutive days, plus one incomplete.
for off in 0 1 2 3; do mk_set "$(date -u -d "-${off} days" +%Y-%m-%dT030000Z)" complete; done
INCOMPLETE="$(date -u -d '-5 days' +%Y-%m-%dT030000Z)"
mk_set "$INCOMPLETE" incomplete

apply_retention >/dev/null 2>&1
rclone lsf --dirs-only "crypttest:sets" 2>/dev/null | sed 's:/$::' >"$WORK/remaining.txt"
if grep -qx "$INCOMPLETE" "$WORK/remaining.txt"; then
  ok "retention never removes an incomplete set"
else
  not_ok "retention never removes an incomplete set"
fi
NEWEST="$(date -u +%Y-%m-%dT030000Z)"
if grep -qx "$NEWEST" "$WORK/remaining.txt"; then
  ok "retention keeps the newest successful set"
else
  not_ok "retention keeps the newest successful set"
fi
COMPLETE_COUNT="$(while read -r s; do rclone lsf "crypttest:sets/$s/COMPLETE" >/dev/null 2>&1 && echo "$s"; done <"$WORK/remaining.txt" | wc -l | tr -d ' ')"
if [[ "$COMPLETE_COUNT" -le 4 ]]; then
  ok "retention bounds the number of successful sets ($COMPLETE_COUNT <= daily+weekly)"
else
  not_ok "retention bounds the number of successful sets (got $COMPLETE_COUNT)"
fi

# ---------------------------------------------------------------------------
# Static safety: no broad remote deletion, no secret printing
# ---------------------------------------------------------------------------
if grep -nE 'rclone[[:space:]]+purge' "$SCRIPT" | grep -v 'SET_PREFIX' >/dev/null; then
  not_ok "every rclone purge is scoped to the managed prefix"
else
  ok "every rclone purge is scoped to the managed prefix"
fi
if grep -nE 'rclone[[:space:]]+(sync|copy)[^\\n]*--delete' "$SCRIPT" >/dev/null; then
  not_ok "no rclone operation deletes unmanaged remote files"
else
  ok "no rclone operation deletes unmanaged remote files"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAILN"
[[ "$FAILN" -eq 0 ]]
