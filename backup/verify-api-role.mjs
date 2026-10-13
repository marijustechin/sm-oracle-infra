// verify-api-role.mjs — credential-safe end-to-end check of the /auth/me role
// contract (T-023). Runs INSIDE an API-image container on the compose network.
//
// It never prints the password, access tokens, refresh cookie or email body:
// only the observed HTTP statuses and the role values are printed.
//
// Env: API_BASE (e.g. http://api:3000), WEB_ORIGIN (CORS_ORIGIN), TEST_EMAIL,
//      PW_FILE (a file holding the temporary account password).
import { readFileSync } from 'node:fs';

const base = process.env.API_BASE;
const origin = process.env.WEB_ORIGIN;
const email = process.env.TEST_EMAIL;
const password = readFileSync(process.env.PW_FILE, 'utf8').replace(/\r?\n$/, '');

function cookieHeader(res) {
  const list =
    typeof res.headers.getSetCookie === 'function'
      ? res.headers.getSetCookie()
      : [res.headers.get('set-cookie')].filter(Boolean);
  return list.map((c) => c.split(';')[0]).join('; ');
}

async function me(token) {
  const res = await fetch(`${base}/auth/me`, {
    headers: { authorization: `Bearer ${token}` },
  });
  const body = await res.json().catch(() => null);
  return { status: res.status, role: body && body.role };
}

async function run() {
  const login = await fetch(`${base}/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  if (login.status !== 200) {
    console.log(JSON.stringify({ freshLogin: { status: login.status }, error: 'login failed' }));
    return 1;
  }
  const { accessToken } = await login.json();
  const cookie = cookieHeader(login);

  const fresh = await me(accessToken);

  const refresh = await fetch(`${base}/auth/refresh`, {
    method: 'POST',
    headers: { origin, cookie },
  });
  const refreshedToken = refresh.status === 200 ? (await refresh.json()).accessToken : null;
  const restored = refreshedToken
    ? await me(refreshedToken)
    : { status: refresh.status, role: undefined };

  const result = {
    freshLogin: { status: fresh.status, role: fresh.role },
    restoredSession: { status: restored.status, role: restored.role },
  };
  console.log(JSON.stringify(result));

  const ok =
    fresh.status === 200 &&
    typeof fresh.role === 'string' &&
    restored.status === 200 &&
    typeof restored.role === 'string' &&
    fresh.role === restored.role;
  return ok ? 0 : 1;
}

run().then((code) => process.exit(code)).catch((error) => {
  console.log(JSON.stringify({ error: String(error) }));
  process.exit(1);
});
