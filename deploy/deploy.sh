#!/usr/bin/env bash
# Section 7 deployment / rollback — review skeleton.
#
# Not yet exercised against real application images. Run as the human
# administrator with sudo. Image references come from images.env and must be
# immutable `@sha256:` digests; mutable tags are refused.
set -euo pipefail

RELEASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$RELEASE_DIR/compose.yaml"
IMAGES_ENV="$RELEASE_DIR/images.env"
PREV_IMAGES_ENV="$RELEASE_DIR/images.env.prev"
PROJECT="sokoladas-staging"

compose() { docker compose -p "$PROJECT" -f "$COMPOSE_FILE" "$@"; }
die() { echo "deploy: $*" >&2; exit 1; }

require_digest() {
  local value="${1:-}" name="$2"
  [[ "$value" == *"@sha256:"* ]] || die "$name is not an immutable digest (got: ${value:-<unset>}); supply image@sha256:…"
}

load_images() {
  [[ -f "$IMAGES_ENV" ]] || die "missing $IMAGES_ENV"
  # shellcheck disable=SC1090
  set -a; source "$IMAGES_ENV"; set +a
  require_digest "${WEB_IMAGE:-}" "WEB_IMAGE"
  require_digest "${API_IMAGE:-}" "API_IMAGE"
}

validate() {
  load_images
  compose config --quiet || die "compose config failed"
  echo "validate OK: WEB_IMAGE/API_IMAGE are digest-pinned"
}

preflight() {
  validate
  command -v docker >/dev/null || die "docker not found"
  docker info >/dev/null 2>&1 || die "docker daemon unavailable"
  echo "preflight OK"
}

migrate() {
  echo "migrate: prisma migrate deploy (one-shot; exit 0 required) ..."
  compose run --rm migrate
  echo "migrate: schema applied"
}

deploy() {
  preflight
  compose pull frontend api db proxy certbot
  compose up -d db
  migrate
  compose up -d api frontend
  # Recreating the proxy switches it from the maintenance config to the
  # app-routing config; this is the deliberate application-activation step.
  compose up -d proxy certbot
  health
  echo "deploy complete"
}

health() {
  compose ps
  compose exec -T proxy wget -q -O - http://127.0.0.1:8080/health/ready \
    || die "proxy readiness probe failed"
  echo "health OK (proxy readiness); verify external HTTPS and app path separately"
}

rollback() {
  # Re-selects the previous known-good application digests. It does NOT revert
  # database migrations (see docs/deployment.md); a destructive migration must
  # be repaired or restored, not "rolled back" by image selection alone.
  [[ -f "$PREV_IMAGES_ENV" ]] || die "no $PREV_IMAGES_ENV to roll back to"
  cp "$IMAGES_ENV" "$IMAGES_ENV.failed"
  cp "$PREV_IMAGES_ENV" "$IMAGES_ENV"
  validate
  compose pull frontend api
  compose up -d frontend api
  echo "application images rolled back; database schema is NOT automatically reverted"
}

case "${1:-}" in
  deploy) deploy ;;
  rollback) rollback ;;
  preflight) preflight ;;
  validate) validate ;;
  health) health ;;
  migrate) migrate ;;
  *) die "usage: deploy|rollback|preflight|validate|health|migrate" ;;
esac
