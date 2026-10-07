#!/bin/bash
# install-template.sh — administrator operation: install or refresh the
# versioned, root-owned trusted deployment template and the root-owned host-env
# directory used to build releases.
#
# This is an administrator step, not part of the `deploy` account's entry point.
# Run it as root (or via `sudo`) from a reviewed repository checkout:
#
#   sudo deploy/entrypoint/install-template.sh <repo-deploy-dir> [host-env-src]
#
#   <repo-deploy-dir>  the reviewed `deploy/` directory in the repository
#   [host-env-src]     directory holding non-secret smtp.env / google.env; only
#                      needed on first install (later refreshes preserve the
#                      existing root-owned host-env files)
#
# Only the trusted files are copied. `entrypoint/` (the privileged gate itself)
# and per-release manifests under `releases/` are excluded; stage.sh writes the
# selected manifest into each release directory.
set -euo pipefail

TEMPLATE_ROOT="${SOKOLADAS_TEMPLATE_ROOT:-/opt/sokoladas-staging/template}"
HOSTENV_ROOT="${SOKOLADAS_HOSTENV_ROOT:-/etc/sokoladas-staging/hostenv}"

die() { printf 'install-template: %s\n' "$*" >&2; exit 1; }
log() { printf 'install-template: %s\n' "$*"; }

[[ "$(id -u)" -eq 0 ]] || die "must run as root"
[[ $# -ge 1 && $# -le 2 ]] || die "usage: install-template.sh <repo-deploy-dir> [host-env-src]"
SRC_DEPLOY="$(realpath -e "$1")" || die "repository deploy directory not found: $1"
HOSTENV_SRC="${2:-}"

REPO_ROOT="$(cd "$SRC_DEPLOY/.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/resolve_release_manifest.py"

for required in compose.yaml deploy.sh stage.sh proxy/nginx.conf proxy/run-proxy \
  proxy/check-certificate db/init/00-create-roles.sh certbot/run-renewal; do
  [[ -e "$SRC_DEPLOY/$required" ]] || die "source is missing $required"
done
[[ -f "$RESOLVER" ]] || die "source is missing scripts/resolve_release_manifest.py"

# --- host-env: preserve across refreshes, seed on first install ------------

mkdir -p "$HOSTENV_ROOT"
for env_file in smtp.env google.env; do
  if [[ -f "$HOSTENV_ROOT/$env_file" ]]; then
    continue
  fi
  [[ -n "$HOSTENV_SRC" && -f "$HOSTENV_SRC/$env_file" ]] \
    || die "missing $HOSTENV_ROOT/$env_file; provide host-env-src on first install"
  install -o root -g root -m 0644 "$HOSTENV_SRC/$env_file" "$HOSTENV_ROOT/$env_file"
  log "seeded $HOSTENV_ROOT/$env_file"
done
chown root:root "$HOSTENV_ROOT"
chmod 0755 "$HOSTENV_ROOT"
find "$HOSTENV_ROOT" -maxdepth 1 -type f -exec chmod 0644 {} +

# --- build the template ----------------------------------------------------

DEST_PARENT="$(dirname "$TEMPLATE_ROOT")"
mkdir -p "$DEST_PARENT"
NEW="$(mktemp -d "$DEST_PARENT/.template-new.XXXXXX")"
cleanup() { rm -rf "$NEW"; }
trap cleanup EXIT

mkdir -p "$NEW/releases"
cp -a "$SRC_DEPLOY/compose.yaml" "$SRC_DEPLOY/deploy.sh" "$SRC_DEPLOY/stage.sh" "$NEW/"
cp -a "$SRC_DEPLOY/proxy" "$SRC_DEPLOY/db" "$SRC_DEPLOY/certbot" "$SRC_DEPLOY/catalog-import" "$NEW/"
mkdir -p "$NEW/scripts"
cp -a "$RESOLVER" "$NEW/scripts/resolve_release_manifest.py"
for example in "$SRC_DEPLOY"/*.example; do
  [[ -e "$example" ]] || continue
  cp -a "$example" "$NEW/"
done
if [[ -f "$SRC_DEPLOY/releases/README.md" ]]; then
  cp -a "$SRC_DEPLOY/releases/README.md" "$NEW/releases/"
fi
if [[ -f "$SRC_DEPLOY/releases/example-release.json" ]]; then
  cp -a "$SRC_DEPLOY/releases/example-release.json" "$NEW/releases/"
fi

# The version is the reviewed infra commit when it is available, otherwise a
# deterministic hash of the installed template content.
if version="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)" && [[ -n "$version" ]]; then
  :
else
  version="tree-$(cd "$NEW" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')"
fi
printf '%s\n' "$version" >"$NEW/VERSION"

chown -R root:root "$NEW"
chmod -R go-w "$NEW"
find "$NEW" -type d -exec chmod 0755 {} +
find "$NEW" -type f -exec chmod 0644 {} +
for exec_file in deploy.sh stage.sh proxy/run-proxy proxy/check-certificate \
  certbot/run-renewal db/init/00-create-roles.sh catalog-import/run-import.sh; do
  [[ -e "$NEW/$exec_file" ]] && chmod 0755 "$NEW/$exec_file"
done

if [[ -e "$TEMPLATE_ROOT" ]]; then
  backup="${TEMPLATE_ROOT}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$TEMPLATE_ROOT" "$backup"
  log "previous template archived at $backup"
fi
mv "$NEW" "$TEMPLATE_ROOT"
trap - EXIT

log "installed template $version at $TEMPLATE_ROOT"
log "host-env at $HOSTENV_ROOT (smtp.env, google.env; non-secret)"
