#!/usr/bin/env bash
# Deterministic tests for the root-only entry point's staging intake and lock
# (deploy/entrypoint/sokoladas-deploy).
#
# No Oracle access, no sudo, no Docker: the manifest validator, the bounded
# stdin reader and the shared lock are pure functions that can be exercised as a
# non-root user against temporary files.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
ENTRYPOINT="$REPO_ROOT/deploy/entrypoint/sokoladas-deploy"
DEPLOY="$REPO_ROOT/deploy"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export SOKOLADAS_STATE_DIR="$WORK/state"
export SOKOLADAS_LOCK_FILE="$WORK/deploy.lock"
export SOKOLADAS_LOCK_TIMEOUT=1
mkdir -p "$SOKOLADAS_STATE_DIR"

# shellcheck source=/dev/null
source "$ENTRYPOINT"
set +e

PASS=0
FAILN=0
ok() { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
not_ok() { FAILN=$((FAILN + 1)); printf 'FAIL - %s\n' "$1"; }
assert_zero() { if [[ "$2" -eq 0 ]]; then ok "$1"; else not_ok "$1 (expected zero, got $2)"; fi; }
assert_ne0() { if [[ "$2" -ne 0 ]]; then ok "$1"; else not_ok "$1 (expected nonzero)"; fi; }
assert_eq() { if [[ "$2" == "$3" ]]; then ok "$1"; else not_ok "$1 (expected '$3', got '$2')"; fi; }

A="$(python3 -c 'print("a"*64)')"
B="$(python3 -c 'print("b"*64)')"
WEB="ghcr.io/marijustechin/smshop-web@sha256:$A"
API="ghcr.io/marijustechin/smshop-api@sha256:$B"

write_manifest() { # <path> <python-mutation-expression or "" >
  python3 - "$1" "$2" <<'PY'
import json
import sys

path, mutation = sys.argv[1], sys.argv[2]
manifest = {
    "schemaVersion": 1,
    "releaseId": "rel-1",
    "createdAt": "2026-10-07T00:00:00Z",
    "source": {"repository": "github.com/marijustechin/smshop", "commit": "0" * 40, "ref": "main"},
    "ci": {"imagesRunId": "1"},
    "images": {
        "web": {"ref": __import__("os").environ["WEB"], "platform": "linux/arm64", "tag": "sha-" + "0" * 40},
        "api": {"ref": __import__("os").environ["API"], "platform": "linux/arm64", "tag": "sha-" + "0" * 40},
    },
    "infra": {"contractCommit": "infra-sha"},
    "notes": "ok",
}
if mutation:
    exec(mutation)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
PY
}
export WEB API

GOOD="$WORK/good.json"
write_manifest "$GOOD" ""
( validate_manifest rel-1 "$GOOD" ) >/dev/null 2>&1
assert_zero "valid manifest is accepted" $?

reject() { # <label> <mutation>
  local label="$1" mutation="$2" path="$WORK/bad.json"
  write_manifest "$path" "$mutation"
  ( validate_manifest rel-1 "$path" ) >/dev/null 2>&1
  assert_ne0 "$label" $?
}

reject "unsupported top-level field is rejected" 'manifest["deployed"] = True'
reject "unsupported source field is rejected" 'manifest["source"]["token"] = "x"'
reject "unsupported image field is rejected" 'manifest["images"]["web"]["extra"] = 1'
reject "unsupported infra field is rejected" 'manifest["infra"]["extra"] = 1'
reject "unknown repository is rejected" 'manifest["images"]["web"]["ref"] = "ghcr.io/attacker/smshop-web@sha256:" + "a"*64'
reject "mutable tag is rejected" 'manifest["images"]["web"]["ref"] = "ghcr.io/marijustechin/smshop-web:latest"'
reject "wrong platform is rejected" 'manifest["images"]["api"]["platform"] = "linux/amd64"'
reject "short commit is rejected" 'manifest["source"]["commit"] = "abc"'
reject "wrong source repository is rejected" 'manifest["source"]["repository"] = "github.com/attacker/smshop"'
reject "releaseId mismatch is rejected" 'manifest["releaseId"] = "other"'
reject "unsupported schemaVersion is rejected" 'manifest["schemaVersion"] = 2'
reject "missing api image is rejected" 'del manifest["images"]["api"]'
reject "non-object images is rejected" 'manifest["images"] = []'

# release id strictness
( validate_manifest "../escape" "$GOOD" ) >/dev/null 2>&1
assert_ne0 "slash release id is rejected" $?

# ---------------------------------------------------------------------------
# Bounded stdin intake
# ---------------------------------------------------------------------------
OUT="$WORK/stdin.out"
printf '{"ok":true}' | read_bounded_stdin 64 "$OUT"
assert_zero "bounded stdin accepts a small payload" $?
assert_eq "bounded stdin stored the payload" "$(cat "$OUT")" '{"ok":true}'

printf '' | read_bounded_stdin 64 "$OUT"
assert_ne0 "bounded stdin rejects an empty payload" $?

python3 -c 'import sys; sys.stdout.write("x"*100)' | read_bounded_stdin 64 "$OUT"
assert_ne0 "bounded stdin rejects an oversized payload" $?

# ---------------------------------------------------------------------------
# Shared lock
# ---------------------------------------------------------------------------
( acquire_lock ) >/dev/null 2>&1
assert_zero "lock acquisition succeeds when free" $?

( acquire_lock; acquire_lock ) >/dev/null 2>&1
assert_zero "lock is re-entrant within one process" $?

# Hold the lock in a background process and confirm a second attempt fails.
(
  exec 9>"$SOKOLADAS_LOCK_FILE"
  flock -n 9
  sleep 5
) &
HOLDER=$!
sleep 0.4
( acquire_lock ) >/dev/null 2>&1
assert_ne0 "lock contention is refused" $?
kill "$HOLDER" 2>/dev/null
wait "$HOLDER" 2>/dev/null
sleep 0.2
( acquire_lock ) >/dev/null 2>&1
assert_zero "lock is released when the holder exits" $?

# ---------------------------------------------------------------------------
# End-to-end stage through the entry point (non-root test harness)
# ---------------------------------------------------------------------------
IT="$WORK/it"
mkdir -p "$IT/template/releases" "$IT/template/scripts" "$IT/releases" "$IT/hostenv" "$IT/state"
for entry in compose.yaml deploy.sh stage.sh proxy db certbot catalog-import; do
  cp -a "$DEPLOY/$entry" "$IT/template/"
done
cp -a "$DEPLOY"/*.example "$IT/template/" 2>/dev/null || true
cp -a "$REPO_ROOT/scripts/resolve_release_manifest.py" "$IT/template/scripts/resolve_release_manifest.py"
cp -a "$DEPLOY/releases/README.md" "$DEPLOY/releases/example-release.json" "$IT/template/releases/"
printf 'it-template-v1\n' >"$IT/template/VERSION"
cp -a "$DEPLOY/smtp.env.example" "$IT/hostenv/smtp.env"
cp -a "$DEPLOY/google.env.example" "$IT/hostenv/google.env"

IT_MANIFEST="$IT/manifest.json"
write_manifest "$IT_MANIFEST" ""
python3 - "$IT_MANIFEST" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    manifest = json.load(handle)
manifest["releaseId"] = "rel-it"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle)
PY

run_stage() { # <manifest>
  SOKOLADAS_RELEASES_ROOT="$IT/releases" SOKOLADAS_STATE_DIR="$IT/state" \
    SOKOLADAS_TEMPLATE_ROOT="$IT/template" SOKOLADAS_HOSTENV_ROOT="$IT/hostenv" \
    SOKOLADAS_LOCK_FILE="$IT/state/deploy.lock" \
    bash "$ENTRYPOINT" stage rel-it <"$1"
}
run_stage "$IT_MANIFEST" >/dev/null 2>&1
assert_zero "stage through the entry point succeeds" $?
[[ -f "$IT/releases/rel-it/releases/rel-it.json" ]] \
  && ok "entry point staged the release directory" \
  || not_ok "entry point staged the release directory"
assert_eq "no staging leftovers through the entry point" \
  "$(find "$IT/releases" -maxdepth 1 -name '.staging-*' | wc -l | tr -d ' ')" "0"

cp -a "$IT_MANIFEST" "$IT/bad.json"
python3 -c 'import json,sys; p=sys.argv[1]; m=json.load(open(p)); m["releaseId"]="rel-bad"; m["images"]["web"]["ref"]="ghcr.io/attacker/web@sha256:"+"a"*64; json.dump(m,open(p,"w"))' "$IT/bad.json"
run_stage_bad() {
  SOKOLADAS_RELEASES_ROOT="$IT/releases" SOKOLADAS_STATE_DIR="$IT/state" \
    SOKOLADAS_TEMPLATE_ROOT="$IT/template" SOKOLADAS_HOSTENV_ROOT="$IT/hostenv" \
    SOKOLADAS_LOCK_FILE="$IT/state/deploy.lock" \
    bash "$ENTRYPOINT" stage rel-bad <"$IT/bad.json"
}
run_stage_bad >/dev/null 2>&1
assert_ne0 "stage through the entry point rejects a bad manifest" $?
[[ -e "$IT/releases/rel-bad" ]] && not_ok "rejected manifest creates no release" || ok "rejected manifest creates no release"

# An oversized stdin payload is refused before any staging happens.
python3 -c 'import sys; sys.stdout.write("x"*100000)' | \
  SOKOLADAS_RELEASES_ROOT="$IT/releases" SOKOLADAS_STATE_DIR="$IT/state" \
  SOKOLADAS_TEMPLATE_ROOT="$IT/template" SOKOLADAS_HOSTENV_ROOT="$IT/hostenv" \
  SOKOLADAS_LOCK_FILE="$IT/state/deploy.lock" \
  bash "$ENTRYPOINT" stage rel-big >/dev/null 2>&1
assert_ne0 "oversized stdin is refused" $?

printf '\n%s passed, %s failed\n' "$PASS" "$FAILN"
[[ "$FAILN" -eq 0 ]]
