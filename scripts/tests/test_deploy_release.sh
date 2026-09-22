#!/usr/bin/env bash
# Deterministic tests for deploy/deploy.sh release tooling (ARCH-004).
#
# No Docker, no network, no Oracle access: the compose/docker/http functions
# are stubbed and all state lives in a temporary directory.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
DEPLOY_SH="$REPO_ROOT/deploy/deploy.sh"
RESOLVER="$REPO_ROOT/scripts/resolve_release_manifest.py"
COMPOSE_YAML="$REPO_ROOT/deploy/compose.yaml"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export SOKOLADAS_MANIFEST_DIR="$WORK/manifests"
export SOKOLADAS_IMAGES_ENV="$WORK/images.env"
export SOKOLADAS_SMTP_ENV="$WORK/smtp.env"
export SOKOLADAS_STATE_DIR="$WORK/state"
export SOKOLADAS_EVIDENCE_DIR="$WORK/evidence"
export SOKOLADAS_COMPOSE_FILE="$WORK/compose.yaml"
export SOKOLADAS_RESOLVER="$RESOLVER"
export SOKOLADAS_SKIP_PUBLIC=1
mkdir -p "$SOKOLADAS_MANIFEST_DIR" "$SOKOLADAS_STATE_DIR" "$SOKOLADAS_EVIDENCE_DIR"

# shellcheck source=/dev/null
source "$DEPLOY_SH"
set +e

PASS=0
FAILN=0
ok() { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
not_ok() { FAILN=$((FAILN + 1)); printf 'FAIL - %s\n' "$1"; }
assert_eq() { if [[ "$2" == "$3" ]]; then ok "$1"; else not_ok "$1 (expected '$3', got '$2')"; fi; }
assert_ne0() { if [[ "$2" -ne 0 ]]; then ok "$1"; else not_ok "$1 (expected nonzero)"; fi; }
assert_zero() { if [[ "$2" -eq 0 ]]; then ok "$1"; else not_ok "$1 (expected zero, got $2)"; fi; }

A="$(python3 -c 'print("a"*64)')"
B="$(python3 -c 'print("b"*64)')"
WEB_REF="ghcr.io/example/smshop-web@sha256:$A"
API_REF="ghcr.io/example/smshop-api@sha256:$B"

write_manifest() { # <path> <releaseId> <webRef> <apiRef>
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json
import sys

path, rid, web, api = sys.argv[1:5]
manifest = {
    "schemaVersion": 1,
    "releaseId": rid,
    "createdAt": "2026-09-22T00:00:00Z",
    "source": {"repository": "github.com/example/smshop", "commit": "0" * 40, "ref": "main"},
    "ci": {"imagesRunId": "1"},
    "images": {
        "web": {"ref": web, "platform": "linux/arm64", "tag": "sha-" + "0" * 40},
        "api": {"ref": api, "platform": "linux/arm64", "tag": "sha-" + "0" * 40},
    },
    "infra": {"contractCommit": "infra-sha"},
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
PY
}

# Minimal nonsecret environment for load_env().
printf 'WEB_IMAGE=%s\nAPI_IMAGE=%s\n' "$WEB_REF" "$API_REF" >"$SOKOLADAS_IMAGES_ENV"
cat >"$SOKOLADAS_SMTP_ENV" <<'ENV'
SMTP_HOST=smtp.example.invalid
SMTP_PORT=465
SMTP_SECURE=true
SMTP_USER=example
MAIL_FROM="Example <noreply@example.invalid>"
ENV

write_manifest "$SOKOLADAS_MANIFEST_DIR/rel-1.json" "rel-1" "$WEB_REF" "$API_REF"
write_manifest "$SOKOLADAS_MANIFEST_DIR/rel-0.json" "rel-0" "$WEB_REF" "$API_REF"
write_manifest "$SOKOLADAS_MANIFEST_DIR/rel-bad.json" "rel-bad" \
  "ghcr.io/example/smshop-web:latest" "$API_REF"
write_manifest "$SOKOLADAS_MANIFEST_DIR/rel-mismatch.json" "other-id" "$WEB_REF" "$API_REF"

# ---------------------------------------------------------------------------
# Manifest resolution
# ---------------------------------------------------------------------------
manifest_path "rel-1" >/dev/null 2>&1
assert_zero "manifest_path accepts a known release id" $?

manifest_path "does-not-exist" >/dev/null 2>&1
assert_ne0 "unknown release id is rejected" $?

manifest_path "../escape" >/dev/null 2>&1
assert_ne0 "invalid release id is rejected" $?

check_manifest_release "$SOKOLADAS_MANIFEST_DIR/rel-1.json" "rel-1" >/dev/null 2>&1
assert_zero "matching releaseId is accepted" $?

check_manifest_release "$SOKOLADAS_MANIFEST_DIR/rel-mismatch.json" "rel-1" >/dev/null 2>&1
assert_ne0 "releaseId mismatch is rejected" $?

# ---------------------------------------------------------------------------
# images.env staging
# ---------------------------------------------------------------------------
rm -f "$SOKOLADAS_IMAGES_ENV"
stage_images_env "$SOKOLADAS_MANIFEST_DIR/rel-1.json" >/dev/null 2>&1
assert_zero "valid manifest stages images.env" $?
assert_eq "images.env contains exactly the two pins" \
  "$(cat "$SOKOLADAS_IMAGES_ENV")" "WEB_IMAGE=$WEB_REF
API_IMAGE=$API_REF"
assert_eq "images.env has exactly two lines" "$(wc -l <"$SOKOLADAS_IMAGES_ENV" | tr -d ' ')" "2"

cp -f "$SOKOLADAS_IMAGES_ENV" "$WORK/images.env.before"
stage_images_env "$SOKOLADAS_MANIFEST_DIR/rel-bad.json" >/dev/null 2>&1
assert_ne0 "mutable tag manifest is rejected" $?
assert_eq "images.env is unchanged after a rejected manifest" \
  "$(cat "$SOKOLADAS_IMAGES_ENV")" "$(cat "$WORK/images.env.before")"

# Restore good pins for later tests.
stage_images_env "$SOKOLADAS_MANIFEST_DIR/rel-1.json" >/dev/null 2>&1

# ---------------------------------------------------------------------------
# Applied state
# ---------------------------------------------------------------------------
write_applied_state "$SOKOLADAS_MANIFEST_DIR/rel-1.json" "rel-1" "rel-0" >/dev/null 2>&1
assert_zero "write_applied_state succeeds" $?
assert_eq "applied releaseId" "$(read_applied_field releaseId)" "rel-1"
assert_eq "applied previousReleaseId" "$(read_applied_field previousReleaseId)" "rel-0"
assert_eq "applied web digest" \
  "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["images"]["web"])' "$SOKOLADAS_STATE_DIR/applied.json")" \
  "$WEB_REF"
assert_eq "applied has no leftover temp file" \
  "$(ls "$SOKOLADAS_STATE_DIR" | grep -c '\.tmp\.' | tr -d ' ')" "0"
if grep -qiE 'password|secret|token|smtp_password' "$SOKOLADAS_STATE_DIR/applied.json"; then
  not_ok "applied.json contains no secret-like fields"
else
  ok "applied.json contains no secret-like fields"
fi

# ---------------------------------------------------------------------------
# Previous-release / rollback target resolution
# ---------------------------------------------------------------------------
assert_eq "rollback previous resolves to recorded previous release" \
  "$(resolve_rollback_target previous)" "rel-0"
assert_eq "rollback explicit release id resolves" \
  "$(resolve_rollback_target rel-0)" "rel-0"

mv "$SOKOLADAS_STATE_DIR/applied.json" "$WORK/applied.saved"
resolve_rollback_target previous >/dev/null 2>&1
assert_ne0 "rollback previous fails closed without applied state" $?
mv "$WORK/applied.saved" "$SOKOLADAS_STATE_DIR/applied.json"

# ---------------------------------------------------------------------------
# Port-isolation assertion
# ---------------------------------------------------------------------------
compose() {
  case "$*" in
    *"config --format json"*)
      printf '%s' '{"services":{"proxy":{"ports":[{"published":"80"}]},"api":{},"frontend":{},"db":{}}}'
      ;;
    *) return 0 ;;
  esac
}
assert_only_proxy_publishes >/dev/null 2>&1
assert_zero "only-proxy-publishes passes for the expected config" $?

compose() {
  case "$*" in
    *"config --format json"*)
      printf '%s' '{"services":{"proxy":{"ports":[{"published":"80"}]},"api":{"ports":[{"published":"3001"}]}}}'
      ;;
    *) return 0 ;;
  esac
}
assert_only_proxy_publishes >/dev/null 2>&1
assert_ne0 "only-proxy-publishes fails when another service publishes" $?

# ---------------------------------------------------------------------------
# Health propagation
# ---------------------------------------------------------------------------
compose() {
  case "$*" in
    *"config --format json"*) printf '%s' '{"services":{"proxy":{"ports":[{"published":"80"}]}}}' ;;
    exec*)
      [[ "$*" == *"proxy"* ]] && return 0
      return 1
      ;;
    *) return 0 ;;
  esac
}
health >/dev/null 2>&1
assert_ne0 "health fails nonzero when an internal readiness check fails" $?

compose() { case "$*" in *"config --format json"*) printf '%s' '{"services":{"proxy":{"ports":[{"published":"80"}]}}}' ;; *) return 0 ;; esac; }
health >/dev/null 2>&1
assert_zero "health succeeds when all checks pass" $?

# ---------------------------------------------------------------------------
# release: applied state written only after success
# ---------------------------------------------------------------------------
compose() { case "$*" in *"config --format json"*) printf '%s' '{"services":{"proxy":{"ports":[{"published":"80"}]}}}' ;; *) return 0 ;; esac; }
docker_cmd() { return 0; }
rm -f "$SOKOLADAS_STATE_DIR/applied.json"
( release rel-1 ) >/dev/null 2>&1
assert_zero "release success path exits zero" $?
if [[ -f "$SOKOLADAS_STATE_DIR/applied.json" ]]; then
  ok "release success writes applied.json"
  assert_eq "release success applied releaseId" "$(read_applied_field releaseId)" "rel-1"
else
  not_ok "release success writes applied.json"
fi

rm -f "$SOKOLADAS_STATE_DIR/applied.json"
(
  compose() {
    case "$*" in
      pull*) return 1 ;;
      *"config --format json"*) printf '%s' '{"services":{"proxy":{"ports":[{"published":"80"}]}}}' ;;
      *) return 0 ;;
    esac
  }
  release rel-0
) >/dev/null 2>&1
assert_ne0 "release fails nonzero when image pull fails" $?
if [[ -f "$SOKOLADAS_STATE_DIR/applied.json" ]]; then
  not_ok "failed release must not write applied.json"
else
  ok "failed release must not write applied.json"
fi
if ls "$SOKOLADAS_EVIDENCE_DIR" | grep -q 'rel-0'; then
  ok "failed release retains evidence"
else
  not_ok "failed release retains evidence"
fi

# ---------------------------------------------------------------------------
# Static safety: no destructive DB commands / no docker socket / no SSH
# ---------------------------------------------------------------------------
if grep -nE 'down[[:space:]]+(-v|--volumes)|volume[[:space:]]+rm|system[[:space:]]+prune|migrate[[:space:]]+reset|db[[:space:]]+push' "$DEPLOY_SH"; then
  not_ok "deploy.sh contains no DB-volume-destructive command"
else
  ok "deploy.sh contains no DB-volume-destructive command"
fi
if grep -n 'docker.sock' "$COMPOSE_YAML"; then
  not_ok "compose.yaml does not mount the Docker socket"
else
  ok "compose.yaml does not mount the Docker socket"
fi
if grep -nE 'ssh |passwordless|NOPASSWD|docker.sock' "$DEPLOY_SH"; then
  not_ok "deploy.sh adds no SSH/passwordless/socket access"
else
  ok "deploy.sh adds no SSH/passwordless/socket access"
fi

# ---------------------------------------------------------------------------
printf '\n%s passed, %s failed\n' "$PASS" "$FAILN"
[[ "$FAILN" -eq 0 ]]
