#!/bin/bash
# install-release-script.sh — administrator operation: replace only `deploy.sh`
# inside an already-staged release directory with the current trusted template
# deploy.sh, without touching anything else.
#
# It exists to repair the frozen deployment script in a release that was staged
# before a deploy.sh fix, without rebuilding the release or disturbing its
# application image digests, manifest, rollback target or original evidence.
#
#   sudo deploy/entrypoint/install-release-script.sh <release-id>
#
# The command verifies, before and after, that every file in the release
# directory **except deploy.sh** is byte-for-byte unchanged; it refuses to
# proceed if anything else would change.
set -euo pipefail

RELEASES_ROOT="${SOKOLADAS_RELEASES_ROOT:-/opt/sokoladas-staging/releases}"
TEMPLATE_ROOT="${SOKOLADAS_TEMPLATE_ROOT:-/opt/sokoladas-staging/template}"
ID_RE='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'

die() { printf 'install-release-script: %s\n' "$*" >&2; exit 1; }
log() { printf 'install-release-script: %s\n' "$*"; }

[[ "$(id -u)" -eq 0 ]] || die "must run as root"
[[ $# -eq 1 ]] || die "usage: install-release-script.sh <release-id>"
id="$1"
[[ "$id" =~ $ID_RE ]] || die "invalid release id: $id"

target="$RELEASES_ROOT/$id/deploy.sh"
[[ -d "$RELEASES_ROOT/$id" ]] || die "release directory not found: $RELEASES_ROOT/$id"
[[ "$(stat -c '%u' "$RELEASES_ROOT/$id")" == 0 ]] || die "release directory is not root-owned: $RELEASES_ROOT/$id"
sf="$TEMPLATE_ROOT/deploy.sh"
[[ -f "$sf" ]] || die "template deploy.sh not found: $sf"
[[ "$(stat -c '%u' "$sf")" == 0 ]] || die "template deploy.sh is not root-owned: $sf"

# Hash every regular file except deploy.sh, so any collateral change is caught.
hash_rest() {
  ( cd "$RELEASES_ROOT/$id" && find . -type f ! -name deploy.sh -print0 \
      | sort -z | xargs -0 sha256sum ) | sha256sum | awk '{print $1}'
}

before_rest="$(hash_rest)"
before_script="$(sha256sum "$target" | awk '{print $1}')"

install -o root -g root -m 0755 "$sf" "$target"

after_rest="$(hash_rest)"
after_script="$(sha256sum "$target" | awk '{print $1}')"

[[ "$before_rest" == "$after_rest" ]] || die "refusing: files other than deploy.sh changed"
[[ "$before_script" != "$after_script" ]] || log "deploy.sh already identical to the template; no-op"

log "release $id: deploy.sh updated"
log "  before: $before_script"
log "  after:  $after_script"
log "  all other files unchanged (tree hash $after_rest)"
