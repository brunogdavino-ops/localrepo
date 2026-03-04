import { DocumentReference, FieldValue, getFirestore } from 'firebase-admin/firestore';

export interface UpsertClientScoreHistoryParams {
  auditId: string;
  auditRef: DocumentReference;
  auditData: Record<string, unknown>;
  scoreFinal: number;
  scoreByCategory: Record<string, number>;
  scoreVersion: number;
}

type FirestoreLike = ReturnType<typeof getFirestore>;
type BatchLike = { set: (ref: DocumentReference, data: Record<string, unknown>, options: { merge: boolean }) => void };

export async function upsertClientScoreHistory(
  params: UpsertClientScoreHistoryParams,
  deps?: { firestore?: FirestoreLike; writer?: BatchLike }
): Promise<void> {
  const firestore = deps?.firestore ?? getFirestore();
  const clientRef = params.auditData.clientRef as DocumentReference | undefined;

  if (!clientRef) {
    throw new Error(`Auditoria ${params.auditId} sem clientRef.`);
  }

  const historyRef = clientRef.collection('score_history').doc(params.auditId);

  const data = {
    auditRef: params.auditRef,
    auditId: params.auditId,
    clientRef,
    companyRef: (params.auditData.companyRef as DocumentReference | undefined) ?? null,
    scoreFinal: params.scoreFinal,
    scoreByCategory: params.scoreByCategory,
    status: typeof params.auditData.status === 'string' ? params.auditData.status : 'unknown',
    scoredAt: FieldValue.serverTimestamp(),
    scoreVersion: params.scoreVersion,
    updatedAt: FieldValue.serverTimestamp()
  };
  if (deps?.writer) {
    deps.writer.set(historyRef, data, { merge: true });
    return;
  }
  await historyRef.set(data, { merge: true });
}
