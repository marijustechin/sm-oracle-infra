#!/usr/bin/env bash
# sapiensmetric-api-update — bounded scoped API update (T-023).
#
# Run as root (via the scoped wrapper `sapiensmetric-maint-api-update`). It:
#   1. pins the reviewed immutable API image digest (from /etc/sapiensmetric/api-image)
#      into /opt/sapiensmetric-review/images.env;
#   2. runs the explicit migration and recreates the `api` container;
#   3. waits for HTTPS readiness and prints the running image digest;
#   4. runs a CREDENTIAL-SAFE role-contract check (a temporary account created via
#      the operator workflow, exercised through login + refresh + /auth/me) and
#      removes the temporary account and its credential file.
#
# It never prints passwords, tokens or cookies. No arbitrary arguments are
# accepted; all paths and the target digest are fixed by the bootstrap.
set -euo pipefail

PROJECT_DIR=/opt/sapiensmetric-review
IMAGES_ENV="$PROJECT_DIR/images.env"
HOSTENV="$PROJECT_DIR/hostenv"
COMPOSE="$PROJECT_DIR/compose.yaml"
API_IMAGE_FILE=/etc/sapiensmetric/api-image
ROLE_SCRIPT=/usr/local/sbin/verify-api-role.mjs
INITIAL_DIR=/etc/sapiensmetric/initial-credentials
DB_CONTAINER=sapiensmetric-review-db-1
API_URL=https://api.sapiensmetric.eu/health/ready
TEMP_EMAIL=sapiensmetric-rolecheck@example.invalid

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
DB_NAME="$(sed -n 's/^MYSQL_DATABASE=//p' "$HOSTENV" | tr -d '"' | head -1)"
WEB_ORIGIN="$(sed -n 's/^CORS_ORIGIN=//p' "$HOSTENV" | tr -d '"' | head -1)"
[[ -n "$DB_NAME" && -n "$WEB_ORIGIN" ]] || die "hostenv is missing MYSQL_DATABASE or CORS_ORIGIN"

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

# --- credential-safe role-contract check -----------------------------------
check_rc=0
log "role contract check (login + refresh + /auth/me)"
install -d -m 0700 -o root -g root "$INITIAL_DIR"
if compose run --rm --user 0:0 provision --email "$TEMP_EMAIL" --apply \
      --password-out /run/sm-out/rolecheck-pw >/dev/null 2>&1; then
  chmod 0400 "$INITIAL_DIR/rolecheck-pw"
  set +e
  compose run --rm --user 0:0 --entrypoint node \
    -e API_BASE=http://api:3000 -e WEB_ORIGIN="$WEB_ORIGIN" \
    -e TEST_EMAIL="$TEMP_EMAIL" -e PW_FILE=/run/sm-out/rolecheck-pw \
    -v "$ROLE_SCRIPT:/verify-api-role.mjs:ro" \
    api /verify-api-role.mjs
  check_rc=$?
  set -e
else
  log "WARNING: could not create the temporary role-check account"
  check_rc=1
fi
rm -f "$INITIAL_DIR/rolecheck-pw"
# Always remove the temporary account (child rows cascade).
docker exec -i "$DB_CONTAINER" sh -c \
  'MYSQL_PWD="$(cat /run/secrets/mysql_root_password)" exec mysql -uroot "$1"' sh "$DB_NAME" <<SQL
DELETE FROM users WHERE email='$TEMP_EMAIL';
SQL

[[ "$check_rc" -eq 0 ]] || die "role contract check failed (see the JSON above); the temporary account was removed"
log "API update complete; /auth/me serves the role after fresh login and refresh"
