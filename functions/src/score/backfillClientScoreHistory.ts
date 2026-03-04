import { DocumentSnapshot, QueryDocumentSnapshot, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { computeAndPersistScoreForAudit } from './computeAndPersistAuditScore';

type FirestoreLike = ReturnType<typeof getFirestore>;

interface BackfillRequest {
  pageSize?: number;
  maxAudits?: number;
}

interface BackfillResponse {
  processedCount: number;
  successCount: number;
  errorCount: number;
}

function assertIsAdmin(role: string): void {
  if (!['admin', 'owner', 'super_admin'].includes(role)) {
    throw new HttpsError('permission-denied', 'Sem permissao para executar backfill.');
  }
}

async function processAudit(
  auditSnapshot: QueryDocumentSnapshot,
  firestore: FirestoreLike
): Promise<void> {
  const auditRef = firestore.collection('audits').doc(auditSnapshot.id);
  await computeAndPersistScoreForAudit(auditRef, auditSnapshot as DocumentSnapshot, { firestore });
}

export async function backfillClientScoreHistoryHandler(
  request: { auth?: { uid: string } | null; data?: BackfillRequest },
  deps?: { firestore?: FirestoreLike }
): Promise<BackfillResponse> {
  const startedAtMs = Date.now();
  const firestore = deps?.firestore ?? getFirestore();

  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Usuario nao autenticado.');
  }

  const userSnapshot = await firestore.collection('users').doc(request.auth.uid).get();
  const role = (userSnapshot.data()?.role as string | undefined) ?? '';
  assertIsAdmin(role);

  const pageSizeRaw = request.data?.pageSize ?? 50;
  const maxAuditsRaw = request.data?.maxAudits ?? 0;
  const pageSize = Math.max(1, Math.min(200, Number(pageSizeRaw) || 50));
  const maxAudits = Math.max(0, Number(maxAuditsRaw) || 0);

  let processedCount = 0;
  let successCount = 0;
  let errorCount = 0;
  let lastDoc: QueryDocumentSnapshot | null = null;

  while (true) {
    let query = firestore.collection('audits').orderBy('__name__').limit(pageSize);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }
    const page = await query.get();
    if (page.empty) break;

    for (const auditSnapshot of page.docs) {
      if (maxAudits > 0 && processedCount >= maxAudits) break;

      const entryStartMs = Date.now();
      processedCount += 1;
      try {
        await processAudit(auditSnapshot, firestore);
        successCount += 1;
      } catch (error) {
        errorCount += 1;
        console.error('[backfillClientScoreHistory] audit failed', {
          auditId: auditSnapshot.id,
          error: error instanceof Error ? error.message : String(error),
          elapsedMs: Date.now() - entryStartMs
        });
      }
    }

    lastDoc = page.docs[page.docs.length - 1];
    if (maxAudits > 0 && processedCount >= maxAudits) break;
    if (page.size < pageSize) break;
  }

  const totalElapsedMs = Date.now() - startedAtMs;
  console.info('[backfillClientScoreHistory] summary', {
    processedCount,
    successCount,
    errorCount,
    totalElapsedMs
  });

  return {
    processedCount,
    successCount,
    errorCount
  };
}

export const backfillClientScoreHistory = onCall(
  {
    memory: '512MiB',
    timeoutSeconds: 540
  },
  backfillClientScoreHistoryHandler
);
