#!/usr/bin/env bash
# stage.sh — build a root-owned release directory from a validated manifest and
# the versioned, root-owned trusted deployment template.
#
# It is invoked by the root-only entry point /usr/local/sbin/sokoladas-deploy
# (`stage <release-id>`), which reads the manifest from stdin, writes it to a
# private root-owned temporary file and validates its contract. stage.sh can
# also be run directly by an administrator for inspection.
#
# Exactly five positional arguments are accepted so that callers cannot redirect
# paths through the environment:
#
#   stage.sh <release-id> <manifest-file> <releases-root> <template-root> <hostenv-root>
#
# Guarantees:
#   - the manifest is a regular, root-owned file that group/other cannot modify;
#   - the template and host-env trees are root-owned, not group/other writable,
#     and contain no symlinks or special files;
#   - the release is built in a private temporary directory under the releases
#     root and installed with a single atomic rename;
#   - an existing release id is never silently replaced: identical content is an
#     idempotent no-op, different content is rejected;
#   - no secret value is copied. Only non-secret host-only env (smtp.env,
#     google.env) is copied from the root-owned host-env directory; secret files
#     remain under /etc/sokoladas-staging/secrets.
set -euo pipefail

ID_RE='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'

die() { printf 'stage: %s\n' "$*" >&2; exit 1; }
log() { printf 'stage: %s\n' "$*"; }
usage() {
  echo "usage: stage.sh <release-id> <manifest-file> <releases-root> <template-root> <hostenv-root>" >&2
  exit 64
}

[[ $# -eq 5 ]] || usage
ID="$1"
MANIFEST="$2"
RELEASES_ROOT="$3"
TEMPLATE_ROOT="$4"
HOSTENV_ROOT="$5"

# Trusted inputs belong to the owner of the template root (root in a real
# install). Deriving it from the template keeps live checks strict while letting
# the deterministic tests build trees owned by the invoking non-root user.
OWNER_UID="${SOKOLADAS_OWNER_UID:-$(stat -c '%u' "$TEMPLATE_ROOT" 2>/dev/null || echo 0)}"
OWNER_GID="${SOKOLADAS_OWNER_GID:-$(stat -c '%g' "$TEMPLATE_ROOT" 2>/dev/null || echo "$OWNER_UID")}"

[[ "$ID" =~ $ID_RE ]] || die "invalid release id: $ID"
[[ -d "$RELEASES_ROOT" ]] || die "releases root is not a directory: $RELEASES_ROOT"

# --- input safety ---------------------------------------------------------

[[ -f "$MANIFEST" && ! -L "$MANIFEST" ]] || die "manifest is not a regular file: $MANIFEST"
[[ "$(stat -c '%u' "$MANIFEST")" == "$OWNER_UID" ]] || die "manifest is not owned by uid $OWNER_UID: $MANIFEST"
[[ -z "$(find "$MANIFEST" -maxdepth 0 \( -perm -0020 -o -perm -0002 \) -print -quit 2>/dev/null)" ]] \
  || die "manifest is group/other writable: $MANIFEST"

# A trusted input tree must be root-owned and free of group/other writes,
# symlinks and special files.
require_tree() {
  local root="$1" label="$2" offender
  [[ -d "$root" && ! -L "$root" ]] || die "$label is not a directory: $root"
  [[ "$(stat -c '%u' "$root")" == "$OWNER_UID" ]] || die "$label is not owned by uid $OWNER_UID: $root"
  offender="$(find "$root" \( -type l -o \( ! -type d -a ! -type f \) \) -print -quit 2>/dev/null || true)"
  [[ -z "$offender" ]] || die "$label contains a symlink or special file: $offender"
  offender="$(find "$root" \( ! -uid "$OWNER_UID" -o -perm -0020 -o -perm -0002 \) -print -quit 2>/dev/null || true)"
  [[ -z "$offender" ]] || die "$label has a non-$OWNER_UID-owned or group/other-writable entry: $offender"
}
require_tree "$TEMPLATE_ROOT" "template root"
require_tree "$HOSTENV_ROOT" "host-env root"

for required in compose.yaml deploy.sh stage.sh VERSION; do
  [[ -f "$TEMPLATE_ROOT/$required" ]] || die "template is missing $required"
done
for required in smtp.env google.env; do
  [[ -f "$HOSTENV_ROOT/$required" ]] || die "host-env is missing $required"
done

# --- lightweight manifest re-check (the entry point already validated it) ---
python3 - "$MANIFEST" "$ID" <<'PY' || die "manifest rejected"
import json
import sys

path, release_id = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as handle:
        manifest = json.load(handle)
except (OSError, json.JSONDecodeError) as error:
    print(f"stage: manifest is not valid JSON: {error}", file=sys.stderr)
    sys.exit(1)
if manifest.get("schemaVersion") != 1:
    print("stage: unsupported schemaVersion", file=sys.stderr)
    sys.exit(1)
if manifest.get("releaseId") != release_id:
    print("stage: releaseId does not match the requested release", file=sys.stderr)
    sys.exit(1)
PY

TEMPLATE_VERSION="$(head -c 256 "$TEMPLATE_ROOT/VERSION" | tr -d '\n')"
[[ -n "$TEMPLATE_VERSION" ]] || die "template VERSION is empty"

# --- build in a private temporary directory --------------------------------

TMP="$(mktemp -d "$RELEASES_ROOT/.staging-${ID}.XXXXXX")" || die "cannot create staging directory under $RELEASES_ROOT"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Copy the trusted template payload. VERSION and stage.sh are template-management
# files and are not part of a release directory.
shopt -s dotglob nullglob
for entry in "$TEMPLATE_ROOT"/*; do
  base="$(basename "$entry")"
  case "$base" in
    VERSION | stage.sh) continue ;;
  esac
  cp -a "$entry" "$TMP/$base"
done
shopt -u dotglob nullglob

mkdir -p "$TMP/releases"
cp -a "$HOSTENV_ROOT/smtp.env" "$TMP/smtp.env"
cp -a "$HOSTENV_ROOT/google.env" "$TMP/google.env"
cp -a "$MANIFEST" "$TMP/releases/$ID.json"
chmod 0644 "$TMP/releases/$ID.json" "$TMP/smtp.env" "$TMP/google.env"

# Deterministic content hash over the trusted payload. Generated/staging files
# (images.env is written by deploy.sh; stage.json is metadata) are excluded, so
# re-staging an already-released id remains idempotent.
content_hash() {
  local root="$1"
  (
    cd "$root" || exit 1
    find . -type f ! -name stage.json ! -name images.env -print0 \
      | sort -z \
      | while IFS= read -r -d '' file; do
          printf '%s %s ' "$(stat -c '%a' "$file")" "$file"
          sha256sum "$file" | awk '{print $1}'
        done
  ) | sha256sum | awk '{print $1}'
}

HASH="$(content_hash "$TMP")"

# Normalize ownership and modes: only root may write anything in the release.
chown -R "$OWNER_UID:$OWNER_GID" "$TMP"
chmod -R go-w "$TMP"
find "$TMP" -type d -exec chmod 0755 {} +
find "$TMP" -type f -exec chmod a-x {} +
# Restore the executable bit on the scripts the deployment mounts/entrypoints.
for exec_file in deploy.sh stage.sh proxy/run-proxy proxy/check-certificate certbot/run-renewal db/init/00-create-roles.sh catalog-import/run-import.sh; do
  [[ -e "$TMP/$exec_file" ]] && chmod 0755 "$TMP/$exec_file"
done

python3 - "$TMP/stage.json" "$ID" "$TEMPLATE_VERSION" "$HASH" <<'PY'
import datetime
import json
import sys

out, release_id, template_version, content_hash = sys.argv[1:5]
state = {
    "schemaVersion": 1,
    "releaseId": release_id,
    "templateVersion": template_version,
    "contentSha256": content_hash,
    "stagedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
with open(out, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2)
    handle.write("\n")
PY
chmod 0644 "$TMP/stage.json"

# --- atomic install / idempotency -----------------------------------------

TARGET="$RELEASES_ROOT/$ID"
if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  [[ -d "$TARGET" && ! -L "$TARGET" ]] || die "existing release path is not a directory: $TARGET"
  [[ -f "$TARGET/stage.json" ]] || die "release $ID already exists and was not created by stage; refusing to replace"
  existing_hash="$(content_hash "$TARGET")"
  if [[ "$existing_hash" == "$HASH" ]]; then
    log "release $ID already staged with identical content (template $TEMPLATE_VERSION); idempotent no-op"
    exit 0
  fi
  die "release $ID already exists with different content; refusing to replace"
fi

mv "$TMP" "$TARGET"
trap - EXIT
log "staged release $ID from template $TEMPLATE_VERSION"
log "  directory: $TARGET"
log "  manifest:  $TARGET/releases/$ID.json"
