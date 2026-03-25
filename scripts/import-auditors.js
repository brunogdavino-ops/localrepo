const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'auditapp-94b97';
const API_KEY = 'AIzaSyA5dvmJiKpE0kY6_X_vCIPnvxBnvypEFDA';
const COMPANY_ID = 'mWOwPlQ7OlJwyPlq430j';
const DEFAULT_PASSWORD = 'Artezi@123';
const DEFAULT_ROLE = 'auditoria';
const FIREBASE_CLI_CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const FIREBASE_CLI_CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 1) {
    const part = argv[i];
    if (!part.startsWith('--')) continue;
    const key = part.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      args[key] = true;
    } else {
      args[key] = next;
      i += 1;
    }
  }
  return args;
}

function parseCsv(content) {
  const lines = content
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  if (lines.length < 2) return [];

  const headers = lines[0].split(';').map((item) => item.trim());
  return lines.slice(1).map((line) => {
    const values = line.split(';').map((item) => item.trim());
    const row = {};
    headers.forEach((header, index) => {
      row[header] = values[index] ?? '';
    });
    return row;
  });
}

function usersDocUrl(uid) {
  return `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/users/${uid}`;
}

function companyRefValue() {
  return `projects/${PROJECT_ID}/databases/(default)/documents/companies/${COMPANY_ID}`;
}

async function refreshAccessToken(configPath) {
  const raw = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const accessToken = raw?.tokens?.access_token;
  const refreshToken = raw?.tokens?.refresh_token;
  const expiresAt = Number(raw?.tokens?.expires_at || 0);
  const clientId = raw?.user?.aud || raw?.user?.azp || FIREBASE_CLI_CLIENT_ID;

  if (accessToken && Date.now() < expiresAt - 60_000) {
    return accessToken;
  }

  if (!refreshToken || !clientId) {
    throw new Error('Credenciais da Firebase CLI incompletas para renovar token.');
  }

  const params = new URLSearchParams({
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
    client_id: clientId,
    client_secret: FIREBASE_CLI_CLIENT_SECRET,
  });

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params,
  });
  const data = await response.json();
  if (!response.ok || !data.access_token) {
    throw new Error(`Falha ao renovar access token: ${response.status} ${JSON.stringify(data)}`);
  }

  raw.tokens = {
    ...raw.tokens,
    access_token: data.access_token,
    expires_at: Date.now() + Number(data.expires_in || 3600) * 1000,
    expires_in: data.expires_in,
    scope: data.scope,
    token_type: data.token_type,
  };
  fs.writeFileSync(configPath, JSON.stringify(raw, null, 2));
  return data.access_token;
}

async function signUpUser(email, password) {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email,
        password,
        returnSecureToken: false,
      }),
    },
  );
  const data = await response.json();
  if (!response.ok) {
    const message = data?.error?.message || 'UNKNOWN';
    const error = new Error(message);
    error.code = message;
    throw error;
  }
  return data.localId;
}

async function lookupUserByEmail(email, accessToken) {
  const candidates = [
    `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:lookup`,
    'https://identitytoolkit.googleapis.com/v1/accounts:lookup',
  ];

  for (const url of candidates) {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ email: [email] }),
    });
    const data = await response.json().catch(() => ({}));
    if (response.ok) {
      const user = data?.users?.[0];
      if (user?.localId) return user.localId;
      return null;
    }
  }

  return null;
}

async function upsertUsersDoc({ uid, name, email, accessToken }) {
  const response = await fetch(usersDocUrl(uid), {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      fields: {
        name: { stringValue: name },
        email: { stringValue: email },
        role: { stringValue: DEFAULT_ROLE },
        is_active: { booleanValue: true },
        companyref: { referenceValue: companyRefValue() },
      },
    }),
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`Falha ao gravar users/${uid}: ${response.status} ${JSON.stringify(data)}`);
  }
  return data;
}

async function main() {
  const args = parseArgs(process.argv);
  const csvPath = args.csv;
  const dryRun = Boolean(args['dry-run']);

  if (!csvPath) {
    throw new Error('Uso: node import-auditors.js --csv "C:\\caminho\\Auditores.csv" [--dry-run]');
  }

  const resolvedCsv = path.resolve(csvPath);
  const configPath = path.resolve(process.env.USERPROFILE || process.env.HOME, '.config', 'configstore', 'firebase-tools.json');
  const rows = parseCsv(fs.readFileSync(resolvedCsv, 'utf8'));

  if (rows.length === 0) {
    throw new Error('CSV sem linhas válidas.');
  }

  const accessToken = await refreshAccessToken(configPath);
  const results = [];

  for (const row of rows) {
    const name = (row['Nome do Auditor'] || '').trim();
    const email = (row['E-mail de Acesso'] || '').trim().toLowerCase();
    if (!name || !email) continue;

    let uid = null;
    let authAction = 'created';
    try {
      uid = await signUpUser(email, DEFAULT_PASSWORD);
    } catch (error) {
      if (error.code !== 'EMAIL_EXISTS') {
        throw error;
      }
      authAction = 'existing';
      uid = await lookupUserByEmail(email, accessToken);
      if (!uid) {
        throw new Error(`Usuário já existe no Auth, mas não foi possível localizar o UID para ${email}.`);
      }
    }

    if (!dryRun) {
      await upsertUsersDoc({ uid, name, email, accessToken });
    }

    results.push({ name, email, uid, authAction, usersDoc: dryRun ? 'skipped' : 'upserted' });
    console.log(`${email} -> ${uid} (${authAction}${dryRun ? ', dry-run' : ''})`);
  }

  console.log(JSON.stringify({ imported: results.length, dryRun, results }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
