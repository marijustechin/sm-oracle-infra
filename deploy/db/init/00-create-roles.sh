#!/usr/bin/env bash
# PostgreSQL first-boot role creation (runs only on an empty data volume, as the
# postgres OS user, via /docker-entrypoint-initdb.d).
#
# Creates the application and migration roles with logins and passwords read
# from the mounted secret files.
#
# PROVISIONAL: the role names (sokoladas_app, sokoladas_migration), the database
# name and the eventual schema grants are application-owned open fields
# (contract C.1.2/C.1.3). They are placeholder values here and must be replaced
# by the application contract's final DB layout before first initialization;
# they are NOT confirmed facts. Passwords are passed as psql variables so they
# are not rendered into process arguments or logs.
set -euo pipefail

app_password="$(cat /run/secrets/db_init_app_password)"
migration_password="$(cat /run/secrets/db_init_migration_password)"

psql -v ON_ERROR_STOP=1 \
  --username "${POSTGRES_USER}" \
  --dbname "${POSTGRES_DB}" \
  -v app_password="${app_password}" \
  -v migration_password="${migration_password}" <<'SQL'
-- Placeholder role names; replace with the application contract's final values.
CREATE ROLE sokoladas_app WITH LOGIN PASSWORD :'app_password';
CREATE ROLE sokoladas_migration WITH LOGIN PASSWORD :'migration_password';
SQL

echo "created sokoladas_app and sokoladas_migration roles" >&2
