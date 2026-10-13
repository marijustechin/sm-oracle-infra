#!/usr/bin/env bash
# sapiensmetric-api-role-check — credential-safe role-contract check (T-023).
#
# Run as root (via the scoped wrapper `sapiensmetric-maint-api-role-check`). It
# creates a TEMPORARY review account through the operator provisioning workflow,
# exercises `/auth/login` + `/auth/refresh` + `/auth/me` inside an API-image
# container, prints only HTTP statuses and role values (never the password, the
# access token or the refresh cookie), then removes the temporary account and its
# credential file. It does NOT change the running image.
set -euo pipefail

PROJECT_DIR=/opt/sapiensmetric-review
IMAGES_ENV="$PROJECT_DIR/images.env"
HOSTENV="$PROJECT_DIR/hostenv"
COMPOSE="$PROJECT_DIR/compose.yaml"
ROLE_SCRIPT=/usr/local/sbin/verify-api-role.mjs
INITIAL_DIR=/etc/sapiensmetric/initial-credentials
CRED_HOST_FILE="$INITIAL_DIR/rolecheck-pw"
CRED_CONTAINER_PATH=/run/sm-out/rolecheck-pw
DB_CONTAINER=sapiensmetric-review-db-1
TEMP_EMAIL=sapiensmetric-rolecheck@example.invalid

log() { printf 'api-role-check: %s\n' "$*"; }
die() { printf 'api-role-check: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "must run as root"
command -v docker >/dev/null 2>&1 || die "docker not found"
[[ -f "$ROLE_SCRIPT" ]] || die "missing role checker: $ROLE_SCRIPT"
[[ -f "$HOSTENV" ]] || die "missing hostenv: $HOSTENV"

compose() {
  docker compose --project-directory "$PROJECT_DIR" \
    --env-file "$IMAGES_ENV" --env-file "$HOSTENV" -f "$COMPOSE" "$@"
}
DB_NAME="$(sed -n 's/^MYSQL_DATABASE=//p' "$HOSTENV" | tr -d '"' | head -1)"
WEB_ORIGIN="$(sed -n 's/^CORS_ORIGIN=//p' "$HOSTENV" | tr -d '"' | head -1)"
[[ -n "$DB_NAME" && -n "$WEB_ORIGIN" ]] || die "hostenv is missing MYSQL_DATABASE or CORS_ORIGIN"

# Remove any stale credential from an earlier interrupted run.
install -d -m 0700 -o root -g root "$INITIAL_DIR"
rm -f "$CRED_HOST_FILE"

log "creating a temporary review account (operator workflow)"
compose run --rm --user 0:0 provision --email "$TEMP_EMAIL" --apply \
  --password-out "$CRED_CONTAINER_PATH" >/dev/null 2>&1 \
  || die "could not create the temporary role-check account"
[[ -s "$CRED_HOST_FILE" ]] || die "the temporary credential file was not created at $CRED_HOST_FILE"
chmod 0400 "$CRED_HOST_FILE"

# The verification container must have BOTH the checker and the credential
# directory mounted; the earlier failure was a missing credential mount (ENOENT).
rc=0
compose run --rm --user 0:0 --entrypoint node \
  -e API_BASE=http://api:3000 -e WEB_ORIGIN="$WEB_ORIGIN" \
  -e TEST_EMAIL="$TEMP_EMAIL" -e PW_FILE="$CRED_CONTAINER_PATH" \
  -v "$ROLE_SCRIPT:/verify-api-role.mjs:ro" \
  -v "$INITIAL_DIR:/run/sm-out:ro" \
  api /verify-api-role.mjs || rc=$?

# Always clean up: the temporary credential file and the temporary account
# (child rows cascade; the owner account is never touched).
rm -f "$CRED_HOST_FILE"
docker exec -i "$DB_CONTAINER" sh -c \
  'MYSQL_PWD="$(cat /run/secrets/mysql_root_password)" exec mysql -uroot "$1"' sh "$DB_NAME" <<SQL \
  || die "temporary account cleanup failed"
DELETE FROM users WHERE email='$TEMP_EMAIL';
SQL

[[ "$rc" -eq 0 ]] || die "role contract check failed (temporary account removed)"
log "role contract check passed (fresh login + restored session); temporary account removed"
