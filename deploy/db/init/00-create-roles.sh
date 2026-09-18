#!/usr/bin/env bash
# PostgreSQL first-boot role creation (runs only on an empty data volume, as the
# postgres OS user, via /docker-entrypoint-initdb.d).
#
# Creates the application (runtime) and migration (schema-owner) roles with
# logins and passwords read from the mounted secret files, and grants the
# runtime role the privileges it needs to use the schema the migration role
# creates.
#
# Role names `sokoladas_app` (runtime) and `sokoladas_migration` (migrations)
# are the deployment contract's confirmed values (compose.yaml: `DB_USER`).
# Passwords are passed as psql variables so they are not rendered into process
# arguments or logs.
#
# Design (validated locally against PostgreSQL 18 on 2026-09-15):
#   - the migration role may create objects in `public`;
#   - the runtime role may only USE the schema and DML the tables/sequences the
#     migration role creates (its default privileges apply to future objects);
#   - the runtime role must not perform DDL.
set -euo pipefail

app_password="$(cat /run/secrets/db_init_app_password)"
migration_password="$(cat /run/secrets/db_init_migration_password)"

psql -v ON_ERROR_STOP=1 \
  --username "${POSTGRES_USER}" \
  --dbname "${POSTGRES_DB}" \
  -v app_password="${app_password}" \
  -v migration_password="${migration_password}" <<'SQL'
CREATE ROLE sokoladas_app WITH LOGIN PASSWORD :'app_password';
CREATE ROLE sokoladas_migration WITH LOGIN PASSWORD :'migration_password';

-- Schema-level separation: migration owns DDL, runtime has usage only.
GRANT CREATE, USAGE ON SCHEMA public TO sokoladas_migration;
GRANT USAGE ON SCHEMA public TO sokoladas_app;

-- Future objects created by the migration role are usable by the runtime role.
ALTER DEFAULT PRIVILEGES FOR ROLE sokoladas_migration IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO sokoladas_app;
ALTER DEFAULT PRIVILEGES FOR ROLE sokoladas_migration IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO sokoladas_app;
SQL

echo "created sokoladas_app and sokoladas_migration roles with grants" >&2
