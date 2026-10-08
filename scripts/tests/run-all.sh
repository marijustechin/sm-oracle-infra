#!/usr/bin/env bash
# Authoritative aggregate test gate for sm-oracle-infra.
#
# Runs every infrastructure test suite in isolation (temporary fixtures, no
# Oracle, no Google Drive, no real secrets, no live application data) and
# propagates any suite failure as a nonzero exit. Missing required tooling is
# reported explicitly — suites are never silently skipped.
#
# Local and CI both run exactly this command:
#   bash scripts/tests/run-all.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Declared runtime prerequisites. CI provisions rclone; docker and the rest are
# standard on the GitHub ubuntu-latest runner.
REQUIRED_TOOLS=(bash python3 node rclone docker git flock tar sha256sum mktemp)

missing=()
for tool in "${REQUIRED_TOOLS[@]}"; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "run-all: missing required tools: ${missing[*]}" >&2
  echo "run-all: install them before running the infrastructure test gate (no suite is silently skipped)." >&2
  exit 2
fi

suites=(
  "deploy release:bash scripts/tests/test_deploy_release.sh"
  "deploy google wiring:bash scripts/tests/test_deploy_google.sh"
  "entry point:bash scripts/tests/test_entrypoint.sh"
  "staging:bash scripts/tests/test_stage.sh"
  "backup:bash scripts/tests/test_backup.sh"
  "release manifest resolver:python3 scripts/tests/test_resolve_release_manifest.py"
  "workflow checker fixtures:node --test scripts/ci/check-workflow.test.mjs"
)

results=()
failed=0
for entry in "${suites[@]}"; do
  name="${entry%%:*}"
  cmdline="${entry#*:}"
  echo "================================================================================"
  echo "=== [suite] $name"
  echo "=== [command] $cmdline"
  echo "================================================================================"
  # shellcheck disable=SC2086
  if $cmdline; then
    results+=("PASS  $name")
  else
    results+=("FAIL  $name")
    failed=1
  fi
  echo
done

echo "================================================================================"
echo "=== summary"
echo "================================================================================"
printf '%s\n' "${results[@]}"
if [[ "$failed" -eq 0 ]]; then
  echo "infra test gate: OK (${#suites[@]} suites)"
  exit 0
fi
echo "infra test gate: FAILED" >&2
exit 1
