#!/usr/bin/env bash
# Run the explicit catalogue import against the running staging database.
#
# Usage (on the staging host, after `deploy.sh release <id>` has applied the
# migrations):
#   sudo ./run-import.sh <api-image@sha256:...>
#
# It uses the app runtime DB role via the existing host-only secret file, mounts
# the import script + data read-only into the API image, and never opens or
# publishes a database port. Idempotent: safe to re-run.
set -euo pipefail

API_IMAGE_REF="${1:?usage: run-import.sh <api-image@sha256:...>}"
IMPORT_DIR="${CATALOG_IMPORT_DIR:-/opt/sokoladas-staging/catalog-import}"
NETWORK="${SOKOLADAS_DB_NETWORK:-sokoladas-staging_db}"
SECRET_FILE="${SOKOLADAS_DB_APP_PASSWORD_FILE:-/etc/sokoladas-staging/secrets/db_app_password}"

[[ -f "$IMPORT_DIR/import-catalog.mjs" ]] || { echo "missing $IMPORT_DIR/import-catalog.mjs" >&2; exit 1; }
[[ -f "$IMPORT_DIR/catalog.json" ]] || { echo "missing $IMPORT_DIR/catalog.json" >&2; exit 1; }
[[ -f "$SECRET_FILE" ]] || { echo "missing secret $SECRET_FILE" >&2; exit 1; }

docker run --rm \
  --network "$NETWORK" \
  -v "$IMPORT_DIR/import-catalog.mjs:/app/apps/api/import-catalog.mjs:ro" \
  -v "$IMPORT_DIR/catalog.json:/app/apps/api/catalog.json:ro" \
  -v "$SECRET_FILE:/run/secrets/db_app_password:ro" \
  -e DB_HOST=db \
  -e DB_PORT=5432 \
  -e DB_NAME=sokoladas_staging \
  -e DB_USER=sokoladas_app \
  -e DB_PASSWORD_FILE=/run/secrets/db_app_password \
  -e CATALOG_IMPORT_FILE=/app/apps/api/catalog.json \
  --entrypoint node \
  "$API_IMAGE_REF" /app/apps/api/import-catalog.mjs
