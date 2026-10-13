#!/usr/bin/env bash
# sapiensmetric-api-update — bounded scoped API update (T-023).
#
# Run as root (via the scoped wrapper `sapiensmetric-maint-api-update`). It:
#   1. pins the reviewed immutable API image digest (from /etc/sapiensmetric/api-image)
#      into /opt/sapiensmetric-review/images.env;
#   2. runs the explicit migration and recreates the `api` container;
#   3. waits for HTTPS readiness and prints the running image digest;
#   4. delegates to `sapiensmetric-api-role-check` for the credential-safe
#      `/auth/me` role verification (it never prints passwords, tokens or cookies).
#
# It accepts no arguments; all paths and the target digest are fixed by the
# bootstrap. To re-run ONLY the role check (without repeating the rollout), use
# the separate `sapiensmetric-maint-api-role-check` wrapper.
set -euo pipefail

PROJECT_DIR=/opt/sapiensmetric-review
IMAGES_ENV="$PROJECT_DIR/images.env"
HOSTENV="$PROJECT_DIR/hostenv"
COMPOSE="$PROJECT_DIR/compose.yaml"
API_IMAGE_FILE=/etc/sapiensmetric/api-image
API_URL=https://api.sapiensmetric.eu/health/ready
ROLE_CHECK=/usr/local/sbin/sapiensmetric-api-role-check

log() { printf 'api-update: %s\n' "$*"; }
die() { printf 'api-update: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "must run as root"
command -v docker >/dev/null 2>&1 || die "docker not found"
[[ -f "$API_IMAGE_FILE" ]] || die "missing $API_IMAGE_FILE"
IMAGE="$(cat "$API_IMAGE_FILE")"
grep -Eq '^ghcr\.io/marijustechin/sapiensmetric-api@sha256:[0-9a-f]{64}$' <<<"$IMAGE" \
  || die "invalid reviewed API image reference in $API_IMAGE_FILE"

compose() {
  docker compose --project-directory "$PROJECT_DIR" \
    --env-file "$IMAGES_ENV" --env-file "$HOSTENV" -f "$COMPOSE" "$@"
}

log "pinning API_IMAGE -> reviewed digest"
python3 - "$IMAGES_ENV" "$IMAGE" <<'PY'
import os, sys, tempfile
path, image = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines()
out = [f"API_IMAGE={image}" if l.startswith("API_IMAGE=") else l for l in lines]
if not any(l.startswith("API_IMAGE=") for l in lines):
    out.append(f"API_IMAGE={image}")
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
os.write(fd, ("\n".join(out) + "\n").encode())
os.close(fd)
os.chmod(tmp, 0o600)
os.replace(tmp, path)
PY

log "running explicit migration"
compose run --rm migrate

log "recreating the api container"
compose up -d api

log "waiting for HTTPS readiness"
ready=0
for _ in $(seq 1 60); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$API_URL" || echo 000)"
  [[ "$code" == "200" ]] && { ready=1; break; }
  sleep 3
done
[[ "$ready" == "1" ]] || die "api did not become ready after the update"
log "running image: $(docker inspect --format '{{.Config.Image}}' sapiensmetric-review-api-1 2>/dev/null || echo unknown)"

exec "$ROLE_CHECK"
