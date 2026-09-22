#!/usr/bin/env bash
# Section 7 deployment / rollback — manifest-driven release tooling (ARCH-004).
#
# Approved model (Model C): CI builds and publishes immutable images plus a
# non-secret build manifest; the human approves a release manifest; the operator
# runs this script on the host with interactive sudo. This script never contacts
# GitHub and never downloads source; it only pulls pinned images and performs
# read-only public smoke checks.
#
# Image references must be immutable `@sha256:` digests; mutable tags are
# refused. Database migrations are forward-only and are never reversed by this
# script.
#
# Commands:
#   release <release-id>             deploy an approved release manifest end to end
#   rollback <release-id|previous>   restore a previously approved release
#   deploy                           legacy: deploy with the current images.env (no
#                                    applied-state tracking; prefer `release`)
#   validate                         validate compose config with current images.env
#   preflight                        validate + docker availability
#   migrate                          run the one-shot prisma migrate deploy
#   health                           non-destructive health/smoke checks
#
# Host layout (defaults; override with the SOKOLADAS_* environment variables):
#   <release dir>/compose.yaml, /images.env, /smtp.env, /releases/<id>.json
#   /opt/sokoladas-staging/state/applied.json        actual applied release
#   /opt/sokoladas-staging/state/history/*.json      applied-release history
#   /opt/sokoladas-staging/evidence/<ts>-<id>/       deployment evidence
#
# Evidence and state contain no secrets.
set -euo pipefail

RELEASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SOKOLADAS_COMPOSE_FILE:-$RELEASE_DIR/compose.yaml}"
IMAGES_ENV="${SOKOLADAS_IMAGES_ENV:-$RELEASE_DIR/images.env}"
SMTP_ENV="${SOKOLADAS_SMTP_ENV:-$RELEASE_DIR/smtp.env}"
MANIFEST_DIR="${SOKOLADAS_MANIFEST_DIR:-$RELEASE_DIR/releases}"
STATE_DIR="${SOKOLADAS_STATE_DIR:-/opt/sokoladas-staging/state}"
EVIDENCE_DIR="${SOKOLADAS_EVIDENCE_DIR:-/opt/sokoladas-staging/evidence}"
APPLIED_FILE="$STATE_DIR/applied.json"
HISTORY_DIR="$STATE_DIR/history"
PROJECT="${SOKOLADAS_PROJECT:-sokoladas-staging}"
DOMAIN="${SOKOLADAS_DOMAIN:-sokoladas.eu}"
SKIP_PUBLIC="${SOKOLADAS_SKIP_PUBLIC:-0}"

compose() { docker compose -p "$PROJECT" -f "$COMPOSE_FILE" "$@"; }
docker_cmd() { docker "$@"; }
die() { echo "deploy: $*" >&2; exit 1; }
fail() { echo "deploy: $*" >&2; return 1; }
log() { echo "deploy: $*"; }

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
operator() { printf '%s' "${SUDO_USER:-$(id -un)}"; }

# --------------------------------------------------------------------------
# Image pins / manifest handling
# --------------------------------------------------------------------------

require_digest() {
  local value="${1:-}" name="$2"
  [[ "$value" == *"@sha256:"* ]] || fail "$name is not an immutable digest (got: ${value:-<unset>}); supply image@sha256:…"
}

resolve_resolver() {
  local candidate
  if [[ -n "${SOKOLADAS_RESOLVER:-}" ]]; then
    [[ -f "$SOKOLADAS_RESOLVER" ]] || die "SOKOLADAS_RESOLVER set but not found: $SOKOLADAS_RESOLVER"
    printf '%s' "$SOKOLADAS_RESOLVER"
    return 0
  fi
  for candidate in \
    "$RELEASE_DIR/resolve_release_manifest.py" \
    "$RELEASE_DIR/scripts/resolve_release_manifest.py" \
    "$RELEASE_DIR/../scripts/resolve_release_manifest.py"; do
    if [[ -f "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  die "resolve_release_manifest.py not found; stage the infra scripts/ (or set SOKOLADAS_RESOLVER)"
}

manifest_path() {
  local id="${1:-}" path
  [[ -n "$id" ]] || { fail "release id required"; return 1; }
  [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || { fail "invalid release id: $id"; return 1; }
  path="$MANIFEST_DIR/$id.json"
  [[ -f "$path" ]] || { fail "release manifest not found: $path"; return 1; }
  printf '%s' "$path"
}

# Extract a scalar field (dotted path) from a manifest; empty string if absent.
manifest_field() {
  local manifest="$1" keypath="$2"
  python3 - "$manifest" "$keypath" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
for part in sys.argv[2].split("."):
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        value = ""
        break
if value is None:
    value = ""
print(value)
PY
}

check_manifest_release() {
  local manifest="$1" expected="$2" actual commit
  actual="$(manifest_field "$manifest" "releaseId")"
  [[ "$actual" == "$expected" ]] || { fail "manifest releaseId '$actual' does not match requested '$expected'"; return 1; }
  commit="$(manifest_field "$manifest" "source.commit")"
  [[ -n "$commit" ]] || { fail "manifest is missing source.commit"; return 1; }
}

# Validate the approved manifest and atomically write the host-only images.env.
stage_images_env() {
  local manifest="$1" resolver tmp
  resolver="$(resolve_resolver)" || return 1
  tmp="${IMAGES_ENV}.tmp.$$"
  if ! python3 "$resolver" "$manifest" --out "$tmp" >/dev/null; then
    rm -f "$tmp"
    fail "release manifest rejected by resolver: $manifest"
    return 1
  fi
  mv -f "$tmp" "$IMAGES_ENV"
}

# --------------------------------------------------------------------------
# Applied state (host-only; never committed)
# --------------------------------------------------------------------------

read_applied_field() {
  local field="$1"
  [[ -f "$APPLIED_FILE" ]] || return 1
  python3 - "$APPLIED_FILE" "$field" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
except (OSError, json.JSONDecodeError):
    sys.exit(1)
value = data.get(sys.argv[2])
if value is None or value == "":
    sys.exit(1)
print(value)
PY
}

# Write applied.json atomically. Call only after a successful deployment.
write_applied_state() {
  local manifest="$1" id="$2" previous="$3" tmp
  mkdir -p "$STATE_DIR" || return 1
  tmp="${APPLIED_FILE}.tmp.$$"
  python3 - "$manifest" "$id" "${previous:-}" "$(now_utc)" "$(operator)" >"$tmp" <<'PY'
import json
import sys

manifest_path, release_id, previous, applied_at, applied_by = sys.argv[1:6]
with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)
images = manifest.get("images", {})
state = {
    "schemaVersion": 1,
    "releaseId": release_id,
    "appliedAt": applied_at,
    "appliedBy": applied_by,
    "source": manifest.get("source", {}),
    "images": {
        "web": images.get("web", {}).get("ref"),
        "api": images.get("api", {}).get("ref"),
    },
    "infra": manifest.get("infra", {}),
    "previousReleaseId": previous or None,
}
json.dump(state, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
  mv -f "$tmp" "$APPLIED_FILE"
}

record_history() {
  local stamp="$1" id="$2" kind="$3"
  mkdir -p "$HISTORY_DIR" || return 1
  [[ -f "$APPLIED_FILE" ]] || return 1
  cp -f "$APPLIED_FILE" "$HISTORY_DIR/${stamp}-${kind}-${id}.json"
}

resolve_rollback_target() {
  local arg="${1:-}" target
  if [[ "$arg" == "previous" ]]; then
    target="$(read_applied_field previousReleaseId || true)"
    [[ -n "$target" ]] || { fail "no previous applied release recorded; specify an explicit release id"; return 1; }
  else
    target="$arg"
  fi
  [[ -n "$target" ]] || { fail "rollback target required"; return 1; }
  printf '%s' "$target"
}

# --------------------------------------------------------------------------
# Evidence (host-only; non-secret)
# --------------------------------------------------------------------------

write_summary_header() {
  local evidence="$1" id="$2" commit="$3" web="$4" api="$5" infra="$6" previous="$7"
  {
    echo "releaseId: $id"
    echo "startedAt: $(now_utc)"
    echo "operator: $(operator)"
    echo "sourceCommit: ${commit:-<unknown>}"
    echo "webImage: ${web:-<unknown>}"
    echo "apiImage: ${api:-<unknown>}"
    echo "infraCommit: ${infra:-<none>}"
    echo "previousReleaseId: ${previous:-<none>}"
  } >"$evidence/summary.txt"
}

write_summary_footer() {
  local evidence="$1" status="$2"
  {
    echo "finalStatus: $status"
    echo "finishedAt: $(now_utc)"
  } >>"$evidence/summary.txt"
}

finish_failure() {
  local evidence="$1" id="$2" stage="$3" message="$4"
  {
    echo "failureStage: $stage"
    echo "failureMessage: $message"
    echo "finalStatus: failure"
    echo "finishedAt: $(now_utc)"
  } >>"$evidence/summary.txt"
  echo "deploy: FAILED at $stage: $message" >&2
  echo "deploy: evidence retained at $evidence" >&2
  echo "deploy: applied state NOT changed (release $id is not marked applied)" >&2
  exit 1
}

# --------------------------------------------------------------------------
# Environment / compose helpers
# --------------------------------------------------------------------------

load_env() {
  [[ -f "$IMAGES_ENV" ]] || { fail "missing $IMAGES_ENV (generate it from a release manifest with: ./deploy.sh release <id>)"; return 1; }
  [[ -f "$SMTP_ENV" ]] || { fail "missing $SMTP_ENV (nonsecret SMTP_HOST/SMTP_PORT/SMTP_SECURE/SMTP_USER/MAIL_FROM)"; return 1; }
  # shellcheck disable=SC1090
  set -a; source "$IMAGES_ENV"; source "$SMTP_ENV"; set +a
  require_digest "${WEB_IMAGE:-}" "WEB_IMAGE" || return 1
  require_digest "${API_IMAGE:-}" "API_IMAGE" || return 1
  local name
  for name in SMTP_HOST SMTP_PORT SMTP_SECURE SMTP_USER MAIL_FROM; do
    [[ -n "${!name:-}" ]] || { fail "$name must be set in $SMTP_ENV"; return 1; }
  done
}

assert_only_proxy_publishes() {
  local published
  published="$(compose config --format json | python3 -c '
import json
import sys

data = json.load(sys.stdin)
services = data.get("services", {})
print(" ".join(sorted(name for name, svc in services.items() if svc.get("ports"))))
')" || { fail "could not determine published ports from compose config"; return 1; }
  [[ "$published" == "proxy" ]] || { fail "unexpected published ports on: ${published:-<none>} (only the proxy may publish 80/443)"; return 1; }
  echo "published ports OK (proxy only)"
}

validate() {
  load_env || return 1
  compose config --quiet || { fail "compose config failed"; return 1; }
  echo "validate OK: WEB_IMAGE/API_IMAGE are digest-pinned; SMTP settings present"
}

preflight_docker() {
  command -v docker >/dev/null 2>&1 || { fail "docker not found"; return 1; }
  docker_cmd info >/dev/null 2>&1 || { fail "docker daemon unavailable"; return 1; }
  echo "preflight OK"
}

preflight() {
  validate || return 1
  preflight_docker || return 1
}

migrate() {
  echo "migrate: prisma migrate deploy (one-shot; exit 0 required) ..."
  compose run --rm migrate || { fail "migration failed; refusing to start application services"; return 1; }
  echo "migrate: schema applied"
}

http_status() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$1" 2>/dev/null || echo "000"
}

check_status() {
  local url="$1" expected="$2" label="$3" code
  code="$(http_status "$url")"
  if [[ "$code" != "$expected" ]]; then
    echo "health: $label expected $expected, got $code ($url)" >&2
    return 1
  fi
  return 0
}

check_public() {
  local rc=0
  check_status "https://$DOMAIN/" 200 "apex HTTPS" || rc=1
  check_status "https://www.$DOMAIN/" 308 "www->apex redirect" || rc=1
  check_status "http://$DOMAIN/" 308 "HTTP->HTTPS redirect" || rc=1
  check_status "https://$DOMAIN/.well-known/acme-challenge/deploy-nonexistent" 404 "ACME path" || rc=1
  check_status "https://$DOMAIN/api/auth/me" 401 "unauthenticated /api/auth/me" || rc=1
  return "$rc"
}

check_internal() {
  local rc=0
  compose exec -T proxy wget -q -O /dev/null http://127.0.0.1:8080/health/ready \
    || { echo "health: proxy readiness FAILED" >&2; rc=1; }
  compose exec -T frontend wget -q -O /dev/null http://127.0.0.1:3000/health/ready \
    || { echo "health: frontend readiness FAILED" >&2; rc=1; }
  compose exec -T api wget -q -O /dev/null http://127.0.0.1:3001/health/ready \
    || { echo "health: API readiness FAILED" >&2; rc=1; }
  return "$rc"
}

# Non-destructive health/smoke checks. Creates no data; never mutates state.
health() {
  load_env || return 1
  local rc=0
  echo "health: docker compose ps"
  compose ps
  echo "health: internal readiness"
  check_internal || rc=1
  echo "health: published-port assertion"
  assert_only_proxy_publishes || rc=1
  if [[ "$SKIP_PUBLIC" == "1" ]]; then
    echo "health: public smoke skipped (SOKOLADAS_SKIP_PUBLIC=1)"
  else
    echo "health: public smoke"
    check_public || rc=1
  fi
  if [[ "$rc" -eq 0 ]]; then
    echo "health: OK"
  fi
  return "$rc"
}

# --------------------------------------------------------------------------
# Release / rollback / legacy deploy
# --------------------------------------------------------------------------

release() {
  local id="${1:-}" manifest ts evidence
  manifest="$(manifest_path "$id")" || return 1
  check_manifest_release "$manifest" "$id" || return 1

  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  evidence="$EVIDENCE_DIR/${ts}-${id}"
  mkdir -p "$evidence" "$STATE_DIR" "$HISTORY_DIR" || { fail "cannot create state/evidence directories"; return 1; }
  cp -f "$manifest" "$evidence/release.json"

  local commit web_ref api_ref infra previous
  commit="$(manifest_field "$manifest" "source.commit")"
  web_ref="$(manifest_field "$manifest" "images.web.ref")"
  api_ref="$(manifest_field "$manifest" "images.api.ref")"
  infra="$(manifest_field "$manifest" "infra.contractCommit")"
  previous="$(read_applied_field releaseId || true)"
  write_summary_header "$evidence" "$id" "$commit" "$web_ref" "$api_ref" "$infra" "$previous"

  log "[1/8] staging host-only images.env from approved manifest"
  stage_images_env "$manifest" >"$evidence/resolver.log" 2>&1 || finish_failure "$evidence" "$id" "manifest" "release manifest rejected"
  cp -f "$IMAGES_ENV" "$evidence/images.env"

  log "[2/8] loading environment"
  load_env >"$evidence/env.log" 2>&1 || finish_failure "$evidence" "$id" "env" "environment files missing or invalid"

  log "[3/8] validating compose config and port isolation"
  compose config --quiet >"$evidence/compose-config.log" 2>&1 || finish_failure "$evidence" "$id" "compose-config" "compose config invalid"
  assert_only_proxy_publishes >"$evidence/ports.log" 2>&1 || finish_failure "$evidence" "$id" "ports" "unexpected published ports"

  log "[4/8] preflight (docker)"
  preflight_docker >"$evidence/preflight.log" 2>&1 || finish_failure "$evidence" "$id" "preflight" "docker unavailable"

  log "[5/8] pulling pinned images (before touching running services)"
  compose pull frontend api db proxy certbot >"$evidence/pull.log" 2>&1 || finish_failure "$evidence" "$id" "pull" "image pull failed; running release untouched"

  log "[6/8] starting database and applying migrations (explicit)"
  compose up -d --wait db >"$evidence/db-up.log" 2>&1 || finish_failure "$evidence" "$id" "db" "database failed to become healthy"
  migrate >"$evidence/migration.log" 2>&1 || finish_failure "$evidence" "$id" "migration" "migration failed; application services not started"

  log "[7/8] starting application and edge services"
  compose up -d api frontend >"$evidence/app-up.log" 2>&1 || finish_failure "$evidence" "$id" "app-up" "application services failed to start"
  compose up -d proxy certbot >"$evidence/edge-up.log" 2>&1 || finish_failure "$evidence" "$id" "edge-up" "proxy/certbot failed to start"

  log "[8/8] health and smoke checks"
  if ! health >"$evidence/health.log" 2>&1; then
    finish_failure "$evidence" "$id" "health" "health/smoke checks failed; rollback: sudo ./deploy.sh rollback previous"
  fi

  write_applied_state "$manifest" "$id" "$previous" || finish_failure "$evidence" "$id" "state" "could not write applied state"
  record_history "$ts" "$id" "release" || true
  write_summary_footer "$evidence" "success"
  log "release $id applied"
  log "  web: $web_ref"
  log "  api: $api_ref"
  if [[ -n "$previous" ]]; then
    log "  previous release: $previous (rollback: sudo ./deploy.sh rollback previous)"
  fi
  log "  evidence: $evidence"
}

rollback() {
  local arg="${1:-}" target manifest ts evidence current
  [[ -n "$arg" ]] || die "usage: rollback <release-id|previous>"
  target="$(resolve_rollback_target "$arg")" || return 1
  manifest="$(manifest_path "$target")" || return 1
  check_manifest_release "$manifest" "$target" || return 1

  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  evidence="$EVIDENCE_DIR/${ts}-rollback-to-${target}"
  mkdir -p "$evidence" "$STATE_DIR" "$HISTORY_DIR" || { fail "cannot create state/evidence directories"; return 1; }
  cp -f "$manifest" "$evidence/release.json"
  current="$(read_applied_field releaseId || true)"

  local commit web_ref api_ref infra
  commit="$(manifest_field "$manifest" "source.commit")"
  web_ref="$(manifest_field "$manifest" "images.web.ref")"
  api_ref="$(manifest_field "$manifest" "images.api.ref")"
  infra="$(manifest_field "$manifest" "infra.contractCommit")"
  write_summary_header "$evidence" "$target" "$commit" "$web_ref" "$api_ref" "$infra" "$current"

  log "rollback: target=$target (current=${current:-none})"
  log "WARNING: image rollback does NOT revert database migrations."
  log "WARNING: if the current release applied a non-backward-compatible migration, restore from backup may be required."

  log "[1/6] staging host-only images.env from approved manifest"
  stage_images_env "$manifest" >"$evidence/resolver.log" 2>&1 || finish_failure "$evidence" "$target" "manifest" "rollback manifest rejected"
  cp -f "$IMAGES_ENV" "$evidence/images.env"

  log "[2/6] loading environment and validating config"
  load_env >"$evidence/env.log" 2>&1 || finish_failure "$evidence" "$target" "env" "environment files missing or invalid"
  compose config --quiet >"$evidence/compose-config.log" 2>&1 || finish_failure "$evidence" "$target" "compose-config" "compose config invalid"
  assert_only_proxy_publishes >"$evidence/ports.log" 2>&1 || finish_failure "$evidence" "$target" "ports" "unexpected published ports"
  preflight_docker >"$evidence/preflight.log" 2>&1 || finish_failure "$evidence" "$target" "preflight" "docker unavailable"

  log "[3/6] pulling pinned application images"
  compose pull frontend api >"$evidence/pull.log" 2>&1 || finish_failure "$evidence" "$target" "pull" "image pull failed"

  log "[4/6] recreating application services only"
  compose up -d frontend api >"$evidence/app-up.log" 2>&1 || finish_failure "$evidence" "$target" "app-up" "application services failed to start"

  log "[5/6] health and smoke checks"
  health >"$evidence/health.log" 2>&1 || finish_failure "$evidence" "$target" "health" "rollback health/smoke checks failed"

  log "[6/6] recording applied state"
  write_applied_state "$manifest" "$target" "$current" || finish_failure "$evidence" "$target" "state" "could not write applied state"
  record_history "$ts" "$target" "rollback" || true
  write_summary_footer "$evidence" "rollback-success"
  log "rollback applied: $target"
  log "  evidence: $evidence"
}

# Legacy direct deploy using the current images.env (no applied-state tracking).
deploy() {
  preflight || return 1
  compose pull frontend api db proxy certbot
  compose up -d --wait db
  migrate
  compose up -d api frontend
  # Recreating the proxy switches it from maintenance to app routing.
  compose up -d proxy certbot
  health
  log "deploy complete (legacy: no applied-state tracking; prefer 'release <release-id>')"
}

main() {
  case "${1:-}" in
    release) shift; release "${1:-}" ;;
    rollback) shift; rollback "${1:-}" ;;
    deploy) deploy ;;
    preflight) preflight ;;
    validate) validate ;;
    health) health ;;
    migrate) load_env && migrate ;;
    *)
      die "usage: deploy.sh <release <id>|rollback <id|previous>|deploy|preflight|validate|health|migrate>"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
