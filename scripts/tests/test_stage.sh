#!/usr/bin/env bash
# Deterministic tests for deploy/stage.sh: atomic staging, idempotency,
# duplicate rejection, input safety and failure cleanup.
#
# No Oracle access, no sudo, no Docker. The template is built from the reviewed
# repository files; SOKOLADAS_OWNER_UID lets the checks run as a non-root user.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
STAGE_SH="$REPO_ROOT/deploy/stage.sh"
RESOLVER="$REPO_ROOT/scripts/resolve_release_manifest.py"
DEPLOY="$REPO_ROOT/deploy"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export SOKOLADAS_OWNER_UID="$(id -u)"
export SOKOLADAS_OWNER_GID="$(id -g)"

TEMPLATE="$WORK/template"
RELEASES="$WORK/releases"
HOSTENV="$WORK/hostenv"
mkdir -p "$TEMPLATE/releases" "$RELEASES" "$HOSTENV"

build_template() {
  rm -rf "$TEMPLATE"
  mkdir -p "$TEMPLATE/releases" "$TEMPLATE/scripts"
  local entry
  for entry in compose.yaml deploy.sh stage.sh proxy db certbot catalog-import; do
    cp -a "$DEPLOY/$entry" "$TEMPLATE/"
  done
  cp -a "$DEPLOY"/*.example "$TEMPLATE/" 2>/dev/null || true
  cp -a "$RESOLVER" "$TEMPLATE/scripts/resolve_release_manifest.py"
  cp -a "$DEPLOY/releases/README.md" "$DEPLOY/releases/example-release.json" "$TEMPLATE/releases/"
  printf 'test-template-v1\n' >"$TEMPLATE/VERSION"
  cp -a "$DEPLOY/smtp.env.example" "$HOSTENV/smtp.env"
  cp -a "$DEPLOY/google.env.example" "$HOSTENV/google.env"
}
build_template

PASS=0
FAILN=0
ok() { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
not_ok() { FAILN=$((FAILN + 1)); printf 'FAIL - %s\n' "$1"; }
assert_zero() { if [[ "$2" -eq 0 ]]; then ok "$1"; else not_ok "$1 (expected zero, got $2)"; fi; }
assert_ne0() { if [[ "$2" -ne 0 ]]; then ok "$1"; else not_ok "$1 (expected nonzero)"; fi; }
assert_eq() { if [[ "$2" == "$3" ]]; then ok "$1"; else not_ok "$1 (expected '$3', got '$2')"; fi; }

A="$(python3 -c 'print("a"*64)')"
B="$(python3 -c 'print("b"*64)')"
writemanifest() { # <path> <releaseId> [note]
  python3 - "$1" "$2" "${3:-ok}" "$A" "$B" <<'PY'
import json
import sys

path, rid, note, a, b = sys.argv[1:6]
manifest = {
    "schemaVersion": 1,
    "releaseId": rid,
    "createdAt": "2026-10-07T00:00:00Z",
    "source": {"repository": "github.com/marijustechin/smshop", "commit": "0" * 40, "ref": "main"},
    "ci": {"imagesRunId": "1"},
    "images": {
        "web": {"ref": "ghcr.io/marijustechin/smshop-web@sha256:" + a, "platform": "linux/arm64", "tag": "sha-" + "0" * 40},
        "api": {"ref": "ghcr.io/marijustechin/smshop-api@sha256:" + b, "platform": "linux/arm64", "tag": "sha-" + "0" * 40},
    },
    "infra": {"contractCommit": "infra-sha"},
    "notes": note,
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
PY
}

M="$WORK/rel-1.json"
writemanifest "$M" "rel-1"

stage() { bash "$STAGE_SH" "$@"; }
tree_hash() { ( cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum ) | sha256sum | awk '{print $1}'; }
staging_leftovers() { find "$RELEASES" -maxdepth 1 -name '.staging-*' | wc -l | tr -d ' '; }

# ---------------------------------------------------------------------------
# Atomic build
# ---------------------------------------------------------------------------
stage rel-1 "$M" "$RELEASES" "$TEMPLATE" "$HOSTENV" >/dev/null 2>&1
assert_zero "stage builds a new release" $?
for f in deploy.sh compose.yaml smtp.env google.env stage.json releases/rel-1.json scripts/resolve_release_manifest.py; do
  [[ -f "$RELEASES/rel-1/$f" ]] && ok "staged tree contains $f" || not_ok "staged tree contains $f"
done
assert_eq "no staging leftovers after success" "$(staging_leftovers)" "0"

# ---------------------------------------------------------------------------
# Idempotency, including generated images.env
# ---------------------------------------------------------------------------
HASH1="$(tree_hash "$RELEASES/rel-1")"
stage rel-1 "$M" "$RELEASES" "$TEMPLATE" "$HOSTENV" >/dev/null 2>&1
assert_zero "re-staging identical content is idempotent" $?
assert_eq "idempotent re-stage does not change the tree" "$(tree_hash "$RELEASES/rel-1")" "$HASH1"

printf 'WEB_IMAGE=x\n' >"$RELEASES/rel-1/images.env"   # deploy.sh output
stage rel-1 "$M" "$RELEASES" "$TEMPLATE" "$HOSTENV" >/dev/null 2>&1
assert_zero "idempotent re-stage ignores the generated images.env" $?

# ---------------------------------------------------------------------------
# Different content and non-stage directories are refused
# ---------------------------------------------------------------------------
M2="$WORK/rel-1-diff.json"
writemanifest "$M2" "rel-1" "changed"
BEFORE="$(tree_hash "$RELEASES/rel-1")"
stage rel-1 "$M2" "$RELEASES" "$TEMPLATE" "$HOSTENV" >/dev/null 2>&1
assert_ne0 "different content for an existing id is refused" $?
assert_eq "refused re-stage leaves the existing release untouched" "$(tree_hash "$RELEASES/rel-1")" "$BEFORE"
assert_eq "no staging leftovers after a refusal" "$(staging_leftovers)" "0"

mkdir -p "$RELEASES/manual-1"; printf 'x\n' >"$RELEASES/manual-1/deploy.sh"
stage manual-1 "$M" "$RELEASES" "$TEMPLATE" "$HOSTENV" >/dev/null 2>&1
assert_ne0 "an existing directory not created by stage is refused" $?

# ---------------------------------------------------------------------------
# Input safety
# ---------------------------------------------------------------------------
BADOWN="$WORK/badowner.json"; writemanifest "$BADOWN" "ow-1"
SOKOLADAS_OWNER_UID=999999 stage ow-1 "$BADOWN" "$RELEASES" "$TEMPLATE" "$HOSTENV" >/dev/null 2>&1
assert_ne0 "a manifest not owned by the expected uid is refused" $?

chmod g+w "$M"
stage rel-1 "$M" "$RELEASES" "$TEMPLATE" "$HOSTENV" >/dev/null 2>&1
assert_ne0 "a group-writable manifest is refused" $?
chmod g-w "$M"

ln -s /etc/hostname "$TEMPLATE/proxy/evil-link"
stage rel-1 "$M" "$RELEASES" "$TEMPLATE" "$HOSTENV" >/dev/null 2>&1
assert_ne0 "a template containing a symlink is refused" $?
rm -f "$TEMPLATE/proxy/evil-link"

chmod g+w "$TEMPLATE/compose.yaml"
stage rel-1 "$M" "$RELEASES" "$TEMPLATE" "$HOSTENV" >/dev/null 2>&1
assert_ne0 "a group/other-writable template file is refused" $?
chmod g-w "$TEMPLATE/compose.yaml"

(
  mv "$TEMPLATE/compose.yaml" "$TEMPLATE/compose.yaml.saved"
  stage rel-1 "$M" "$RELEASES" "$TEMPLATE" "$HOSTENV" >/dev/null 2>&1
  rc=$?
  mv "$TEMPLATE/compose.yaml.saved" "$TEMPLATE/compose.yaml"
  exit "$rc"
)
assert_ne0 "a template missing a required file is refused" $?

MMIS="$WORK/mismatch.json"; writemanifest "$MMIS" "other-id"
stage rel-1 "$MMIS" "$RELEASES" "$TEMPLATE" "$HOSTENV" >/dev/null 2>&1
assert_ne0 "a manifest whose releaseId mismatches is refused" $?

stage "../escape" "$M" "$RELEASES" "$TEMPLATE" "$HOSTENV" >/dev/null 2>&1
assert_ne0 "an invalid release id is refused" $?

assert_eq "no staging leftovers after all failures" "$(staging_leftovers)" "0"

printf '\n%s passed, %s failed\n' "$PASS" "$FAILN"
[[ "$FAILN" -eq 0 ]]
