#!/usr/bin/env bash
# Deterministic test for the Google OAuth staging wiring (D-005).
#
# Uses the real Compose file with safe dummy values; no Oracle access, no
# network, and no secret values. Verifies the API receives the nonsecret Google
# config and the client secret via the *_FILE model, that the secret host path is
# correct, that SMTP/Turnstile/DB/JWT wiring is unchanged, that only the proxy
# publishes ports, and that a missing Google value fails fast (never a partial
# Google configuration).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
COMPOSE="$REPO_ROOT/deploy/compose.yaml"

A="$(python3 -c 'print("a"*64)')"
B="$(python3 -c 'print("b"*64)')"
export WEB_IMAGE="ghcr.io/example/smshop-web@sha256:$A"
export API_IMAGE="ghcr.io/example/smshop-api@sha256:$B"
export SMTP_HOST=smtp.example.invalid SMTP_PORT=465 SMTP_SECURE=true SMTP_USER=example
export MAIL_FROM='Example <noreply@example.invalid>'
GOOD_CLIENT_ID="example-client-id.apps.googleusercontent.com"
GOOD_CALLBACK="https://sokoladas.eu/api/auth/google/callback"
export GOOGLE_CLIENT_ID="$GOOD_CLIENT_ID"
export GOOGLE_CALLBACK_URL="$GOOD_CALLBACK"

PASS=0
FAILN=0
ok() { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
not_ok() { FAILN=$((FAILN + 1)); printf 'FAIL - %s\n' "$1"; }
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else not_ok "$1 (expected '$3', got '$2')"; fi; }

render_json() { docker compose -p sokoladas-dtest -f "$COMPOSE" config --format json; }

JSON="$(render_json)" || { echo "docker compose config failed"; exit 1; }

get() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2]))" "$JSON" "$1"; }

check "API receives GOOGLE_CLIENT_ID" "$(get "d['services']['api']['environment']['GOOGLE_CLIENT_ID']")" "$GOOD_CLIENT_ID"
check "API receives GOOGLE_CALLBACK_URL" "$(get "d['services']['api']['environment']['GOOGLE_CALLBACK_URL']")" "$GOOD_CALLBACK"
check "API receives GOOGLE_CLIENT_SECRET_FILE" "$(get "d['services']['api']['environment']['GOOGLE_CLIENT_SECRET_FILE']")" "/run/secrets/google_client_secret"
check "API does not receive a direct GOOGLE_CLIENT_SECRET" "$(get "'GOOGLE_CLIENT_SECRET' in d['services']['api']['environment']")" "False"
check "api.secrets includes google_client_secret" \
  "$(get "sorted(s if isinstance(s,str) else s.get('source') for s in d['services']['api'].get('secrets',[]))")" \
  "['db_app_password', 'google_client_secret', 'jwt_access_secret', 'smtp_password', 'turnstile_secret_key']"
check "top-level google secret host path" "$(get "d['secrets']['google_client_secret']['file']")" "/etc/sokoladas-staging/secrets/google_client_secret"
check "SMTP wiring unchanged" "$(get "d['services']['api']['environment']['SMTP_PASSWORD_FILE']")" "/run/secrets/smtp_password"
check "DB wiring unchanged" "$(get "d['services']['api']['environment']['DB_PASSWORD_FILE']")" "/run/secrets/db_app_password"
check "JWT wiring unchanged" "$(get "d['services']['api']['environment']['JWT_ACCESS_SECRET_FILE']")" "/run/secrets/jwt_access_secret"
check "Turnstile wiring unchanged" "$(get "d['services']['api']['environment']['TURNSTILE_SECRET_KEY_FILE']")" "/run/secrets/turnstile_secret_key"
check "only proxy publishes ports" "$(get "sorted(s for s,v in d['services'].items() if v.get('ports'))")" "['proxy']"

# No secret value can appear in rendered output: only the *_FILE path is present.
if printf '%s' "$JSON" | grep -qE 'client-secret|BEGIN .*PRIVATE KEY'; then
  not_ok "rendered compose contains no Google secret value"
else
  ok "rendered compose contains no Google secret value"
fi

# Fail-fast: a missing required Google value must fail the config rather than
# produce a partial Google configuration.
if env -u GOOGLE_CLIENT_ID docker compose -p sokoladas-dtest -f "$COMPOSE" config --quiet >/dev/null 2>&1; then
  not_ok "missing GOOGLE_CLIENT_ID fails fast (no partial Google config)"
else
  ok "missing GOOGLE_CLIENT_ID fails fast (no partial Google config)"
fi
if env -u GOOGLE_CALLBACK_URL docker compose -p sokoladas-dtest -f "$COMPOSE" config --quiet >/dev/null 2>&1; then
  not_ok "missing GOOGLE_CALLBACK_URL fails fast (no partial Google config)"
else
  ok "missing GOOGLE_CALLBACK_URL fails fast (no partial Google config)"
fi

# App-level disabled contract (none set -> google:false) is covered by the
# application unit tests in smshop/apps/api/src/config/env.validation.spec.ts.
printf '\n%s passed, %s failed\n' "$PASS" "$FAILN"
[[ "$FAILN" -eq 0 ]]
