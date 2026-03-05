import {
  DocumentReference,
  DocumentSnapshot,
  FieldValue,
  QueryDocumentSnapshot,
  getFirestore
} from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  AnswerData,
  buildOrderedSections,
  calculateCategoryWeightedScore,
  calculateWeightedScore
} from '../pdf/score';
import { upsertClientScoreHistory } from './upsertClientScoreHistory';

interface ComputeAuditScoreRequest {
  auditId?: string;
}

interface ComputeAuditScoreResponse {
  auditId: string;
  scoreFinal: number;
  scoreByCategoryCount: number;
  scoreVersion: number;
  scoredAt: string;
}

type FirestoreLike = ReturnType<typeof getFirestore>;

function assertCanAccessAudit(
  uid: string,
  userData: Record<string, unknown> | undefined,
  auditData: Record<string, unknown>
): void {
  const role = typeof userData?.role === 'string' ? userData.role : '';
  const isAdmin = ['admin', 'owner', 'super_admin'].includes(String(role));
  const auditorRef = auditData.auditorRef as { id?: string } | undefined;
  const isOwnerAuditor = auditorRef?.id === uid;

  if (!isAdmin && !isOwnerAuditor) {
    throw new HttpsError('permission-denied', 'Sem permissao para calcular score desta auditoria.');
  }
}

interface PersistScoreResult {
  scoreFinal: number;
  scoreByCategory: Record<string, number>;
  scoreVersion: number;
  fetchFirestoreMs: number;
  computeScoreMs: number;
  persistScoreMs: number;
  upsertHistoryMs: number;
}

export async function computeAndPersistScoreForAudit(
  auditRef: DocumentReference,
  auditSnapshot: DocumentSnapshot,
  deps: { firestore: FirestoreLike }
): Promise<PersistScoreResult> {
  const firestore = deps.firestore;
  const auditData = (auditSnapshot.data() ?? {}) as Record<string, unknown>;
  const templateRef = auditData.templateRef as DocumentReference | undefined;
  if (!templateRef) {
    throw new HttpsError('failed-precondition', 'Auditoria sem templateRef.');
  }

  const fetchStartMs = Date.now();
  const answersSnapshotPromise = auditRef.collection('answers').get();
  const questionsSnapshotPromise = firestore
    .collection('questions')
    .where('templateRef', '==', templateRef)
    .orderBy('order')
    .get();
  const categoriesSnapshotPromise = firestore
    .collection('categories')
    .where('templateref', '==', templateRef)
    .orderBy('order')
    .get();
  const [answersSnapshot, questionsSnapshot, categoriesSnapshot] = await Promise.all([
    answersSnapshotPromise,
    questionsSnapshotPromise,
    categoriesSnapshotPromise
  ]);
  const fetchFirestoreMs = Date.now() - fetchStartMs;

  const computeStartMs = Date.now();
  const answers = answersSnapshot.docs.map((doc) => doc.data() as AnswerData);
  const questions = questionsSnapshot.docs as QueryDocumentSnapshot[];
  const sections = buildOrderedSections(categoriesSnapshot.docs as QueryDocumentSnapshot[], questions);

  const scoreFinal = calculateWeightedScore(answers, questions);
  const scoreByCategory: Record<string, number> = {};
  for (const section of sections) {
    scoreByCategory[section.path] = calculateCategoryWeightedScore(section.path, questions, answers);
  }
  const computeScoreMs = Date.now() - computeStartMs;

  const persistStartMs = Date.now();
  const scoreVersion = 1;
  const batch = firestore.batch();
  batch.set(
    auditRef,
    {
      scoreFinal,
      scoreByCategory,
      scoreVersion,
      scoredAt: FieldValue.serverTimestamp()
    },
    { merge: true }
  );
  await upsertClientScoreHistory(
    {
      auditId: auditRef.id,
      auditRef,
      auditData,
      scoreFinal,
      scoreByCategory,
      scoreVersion
    },
    { firestore, writer: batch }
  );
  const persistScoreMs = Date.now() - persistStartMs;

  const upsertStartMs = Date.now();
  await batch.commit();
  const upsertHistoryMs = Date.now() - upsertStartMs;

  return {
    scoreFinal,
    scoreByCategory,
    scoreVersion,
    fetchFirestoreMs,
    computeScoreMs,
    persistScoreMs,
    upsertHistoryMs
  };
}

export async function computeAndPersistAuditScoreHandler(
  request: { auth?: { uid: string } | null; data?: ComputeAuditScoreRequest },
  deps?: { firestore?: FirestoreLike; now?: () => Date }
): Promise<ComputeAuditScoreResponse> {
  const startedAtMs = Date.now();
  const firestore = deps?.firestore ?? getFirestore();
  const now = deps?.now ?? (() => new Date());

  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Usuario nao autenticado.');
  }

  const auditId = typeof request.data?.auditId === 'string' ? request.data.auditId.trim() : '';
  if (!auditId) {
    throw new HttpsError('invalid-argument', 'auditId e obrigatorio.');
  }

  const uid = request.auth.uid;

  const authFetchStartMs = Date.now();
  const auditRef = firestore.collection('audits').doc(auditId);
  const auditSnapshot = await auditRef.get();
  if (!auditSnapshot.exists) {
    throw new HttpsError('not-found', 'Auditoria nao encontrada.');
  }
  const auditData = (auditSnapshot.data() ?? {}) as Record<string, unknown>;

  const userSnapshot = await firestore.collection('users').doc(uid).get();
  const userData = userSnapshot.data() as Record<string, unknown> | undefined;
  assertCanAccessAudit(uid, userData, auditData);
  const authFetchMs = Date.now() - authFetchStartMs;

  let result: PersistScoreResult;
  try {
    result = await computeAndPersistScoreForAudit(auditRef, auditSnapshot, { firestore });
  } catch (error) {
    console.error('[computeAndPersistAuditScore] failed persisting score/history', {
      auditId,
      error: error instanceof Error ? error.message : String(error)
    });
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError('failed-precondition', 'Falha ao persistir score e historico da auditoria.');
  }

  const scoredAt = now().toISOString();
  const totalElapsedMs = Date.now() - startedAtMs;
  console.info('[computeAndPersistAuditScore] perf', {
    auditId,
    authFetchMs,
    fetchFirestoreMs: result.fetchFirestoreMs,
    computeScoreMs: result.computeScoreMs,
    persistScoreMs: result.persistScoreMs,
    upsertHistoryMs: result.upsertHistoryMs,
    totalElapsedMs
  });

  return {
    auditId,
    scoreFinal: result.scoreFinal,
    scoreByCategoryCount: Object.keys(result.scoreByCategory).length,
    scoreVersion: result.scoreVersion,
    scoredAt
  };
}

export const computeAndPersistAuditScore = onCall(
  {
    region: 'southamerica-east1',
    memory: '256MiB',
    timeoutSeconds: 60
  },
  computeAndPersistAuditScoreHandler
);
