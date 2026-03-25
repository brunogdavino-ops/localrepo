const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'auditapp-94b97';
const COMPANY_ID = 'mWOwPlQ7OlJwyPlq430j';
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

function rowValue(row, ...keys) {
  for (const key of keys) {
    if (row[key] !== undefined) return row[key];
  }
  return '';
}

function normalizeText(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .toLowerCase();
}

function cnpjDigits(value) {
  return String(value || '').replace(/\D/g, '');
}

function parseBoolean(value) {
  const normalized = normalizeText(value);
  return ['true', 'sim', 'yes', '1'].includes(normalized);
}

function parsePtBrDate(value) {
  const match = String(value || '').trim().match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (!match) {
    throw new Error(`Data inválida: "${value}". Esperado dd/MM/yyyy.`);
  }
  const [, dd, mm, yyyy] = match;
  return new Date(Date.UTC(Number(yyyy), Number(mm) - 1, Number(dd), 12, 0, 0));
}

function addMonthsUtc(date, months) {
  const targetMonth = date.getUTCMonth() + months;
  const year = date.getUTCFullYear() + Math.floor(targetMonth / 12);
  const month = ((targetMonth % 12) + 12) % 12;
  const lastDay = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  const day = Math.min(date.getUTCDate(), lastDay);
  return new Date(Date.UTC(year, month, day, 12, 0, 0));
}

function nextOccurrenceDate(lastAuditDate, recurrence) {
  switch ((recurrence || '').trim()) {
    case 'Quinzenal':
      return new Date(lastAuditDate.getTime() + 15 * 24 * 60 * 60 * 1000);
    case 'Mensal':
      return addMonthsUtc(lastAuditDate, 1);
    case 'Bimestral':
      return addMonthsUtc(lastAuditDate, 2);
    case 'Trimestral':
      return addMonthsUtc(lastAuditDate, 3);
    default:
      return lastAuditDate;
  }
}

function companyRefValue() {
  return `projects/${PROJECT_ID}/databases/(default)/documents/companies/${COMPANY_ID}`;
}

function configStorePath() {
  return path.resolve(process.env.USERPROFILE || process.env.HOME, '.config', 'configstore', 'firebase-tools.json');
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

function authHeaders(accessToken) {
  return {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${accessToken}`,
  };
}

async function listAllDocuments(collectionName, accessToken) {
  const docs = [];
  let pageToken = '';

  do {
    const query = new URLSearchParams({ pageSize: '500' });
    if (pageToken) query.set('pageToken', pageToken);
    const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${collectionName}?${query}`;
    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(`Falha ao listar ${collectionName}: ${response.status} ${JSON.stringify(data)}`);
    }
    docs.push(...(data.documents || []));
    pageToken = data.nextPageToken || '';
  } while (pageToken);

  return docs;
}

function getFieldValue(field) {
  if (!field) return null;
  if (field.stringValue !== undefined) return field.stringValue;
  if (field.booleanValue !== undefined) return field.booleanValue;
  if (field.timestampValue !== undefined) return field.timestampValue;
  if (field.referenceValue !== undefined) return field.referenceValue;
  if (field.integerValue !== undefined) return Number(field.integerValue);
  if (field.doubleValue !== undefined) return Number(field.doubleValue);
  if (field.nullValue !== undefined) return null;
  if (field.mapValue !== undefined) return field.mapValue.fields || {};
  if (field.arrayValue !== undefined) return field.arrayValue.values || [];
  return null;
}

function buildUsersIndex(userDocs) {
  const byName = new Map();
  for (const doc of userDocs) {
    const name = getFieldValue(doc.fields?.name);
    if (!name) continue;
    byName.set(normalizeText(name), doc);
  }
  return byName;
}

function buildClientsIndex(clientDocs) {
  const byName = new Map();
  for (const doc of clientDocs) {
    const name = getFieldValue(doc.fields?.name);
    if (!name) continue;
    byName.set(normalizeText(name), doc);
  }
  return byName;
}

function referenceValueFromDoc(doc) {
  return `projects/${PROJECT_ID}/databases/(default)/documents/${doc.name.split('/documents/')[1]}`;
}

function buildClientFields(row, auditorDoc) {
  const hasOperator = parseBoolean(rowValue(row, 'hasOperator'));
  const lastAuditDate = parsePtBrDate(rowValue(row, 'last_audit', 'lastAudit'));
  const recurrence = rowValue(row, 'auditrecurrence').trim();
  const nextAuditDate = nextOccurrenceDate(lastAuditDate, recurrence);
  const nowIso = new Date().toISOString();

  const fields = {
    name: { stringValue: rowValue(row, 'name').trim() },
    cnpjDigits: { stringValue: cnpjDigits(rowValue(row, 'cnpjFormatted')) },
    cnpjFormatted: { stringValue: rowValue(row, 'cnpjFormatted').trim() },
    address: { stringValue: rowValue(row, 'address').trim() },
    responsibles: {
      arrayValue: {
        values: [
          {
            mapValue: {
              fields: {
                name: { stringValue: rowValue(row, 'responsible_1_name').trim() },
                email: { stringValue: rowValue(row, 'responsible_1_email').trim().toLowerCase() },
              },
            },
          },
        ],
      },
    },
    hasOperator: { booleanValue: hasOperator },
    responsibilityMap: { mapValue: { fields: {} } },
    auditorRef: { referenceValue: referenceValueFromDoc(auditorDoc) },
    auditrecurrence: { stringValue: recurrence },
    companyref: { referenceValue: companyRefValue() },
    lastAuditDate: { timestampValue: lastAuditDate.toISOString() },
    nextAuditDate: { timestampValue: nextAuditDate.toISOString() },
    updated_at: { timestampValue: nowIso },
  };

  if (hasOperator && rowValue(row, 'operatorName')?.trim()) {
    fields.operatorName = { stringValue: rowValue(row, 'operatorName').trim() };
  } else {
    fields.operatorName = { nullValue: null };
  }

  return fields;
}

async function createClientDocument(fields, accessToken) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/clients`;
  const response = await fetch(url, {
    method: 'POST',
    headers: authHeaders(accessToken),
    body: JSON.stringify({
      fields: {
        ...fields,
        created_at: { timestampValue: new Date().toISOString() },
      },
    }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`Falha ao criar cliente: ${response.status} ${JSON.stringify(data)}`);
  }
  return data;
}

async function updateClientDocument(docName, fields, accessToken) {
  const encoded = docName.split('/documents/')[1];
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${encoded}`;
  const response = await fetch(url, {
    method: 'PATCH',
    headers: authHeaders(accessToken),
    body: JSON.stringify({ fields }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`Falha ao atualizar ${encoded}: ${response.status} ${JSON.stringify(data)}`);
  }
  return data;
}

function auditorLookupName(rawName) {
  const normalized = normalizeText(rawName);
  if (normalized === 'jassica wochner') {
    return 'claudia artezi';
  }
  return normalized;
}

async function main() {
  const args = parseArgs(process.argv);
  const csvPath = args.csv;
  const dryRun = Boolean(args['dry-run']);

  if (!csvPath) {
    throw new Error('Uso: node import-clients.js --csv "C:\\caminho\\Clientes.csv" [--dry-run]');
  }

  const rows = parseCsv(fs.readFileSync(path.resolve(csvPath), 'utf8'));
  if (rows.length === 0) {
    throw new Error('CSV sem linhas válidas.');
  }

  const accessToken = await refreshAccessToken(configStorePath());
  const [userDocs, clientDocs] = await Promise.all([
    listAllDocuments('users', accessToken),
    listAllDocuments('clients', accessToken),
  ]);
  const usersByName = buildUsersIndex(userDocs);
  const clientsByName = buildClientsIndex(clientDocs);

  const unresolved = rows
    .map((row) => rowValue(row, 'auditorname', 'auditorName')?.trim())
    .filter(Boolean)
    .filter((name, index, list) => list.indexOf(name) === index)
    .filter((name) => !usersByName.has(auditorLookupName(name)));

  if (unresolved.length > 0) {
    throw new Error(`Auditoras não encontradas em users: ${unresolved.join(', ')}`);
  }

  const results = [];
  for (const row of rows) {
    const clientName = rowValue(row, 'name').trim();
    const auditorName = rowValue(row, 'auditorname', 'auditorName').trim();
    const normalizedClientName = normalizeText(clientName);
    const auditorDoc = usersByName.get(auditorLookupName(auditorName));
    const fields = buildClientFields(row, auditorDoc);

    let action = 'created';
    let documentName = null;
    const existingClient = clientsByName.get(normalizedClientName);

    if (!dryRun) {
      if (existingClient) {
        await updateClientDocument(existingClient.name, fields, accessToken);
        action = 'updated';
        documentName = existingClient.name;
      } else {
        const created = await createClientDocument(fields, accessToken);
        documentName = created.name;
      }
    } else if (existingClient) {
      action = 'would-update';
      documentName = existingClient.name;
    }

    results.push({
      name: clientName,
      auditorname: auditorName,
      action: dryRun ? action : action,
      lastAuditDate: rowValue(row, 'last_audit', 'lastAudit'),
      recurrence: rowValue(row, 'auditrecurrence'),
      doc: documentName,
    });
    console.log(`${clientName} -> ${dryRun ? action : action}`);
  }

  console.log(JSON.stringify({ imported: results.length, dryRun, results }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
