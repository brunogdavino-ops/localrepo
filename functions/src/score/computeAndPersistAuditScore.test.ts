import { computeAndPersistAuditScoreHandler } from './computeAndPersistAuditScore';

function makeDoc(path: string, data: Record<string, unknown>) {
  const parts = path.split('/');
  return {
    id: parts[parts.length - 1],
    ref: { path },
    data: () => data
  } as any;
}

function makeFirestoreMock(options: {
  auditExists: boolean;
  role?: string;
  auditorUid?: string;
  answers?: Array<Record<string, unknown>>;
  questions?: Array<{ path: string; data: Record<string, unknown> }>;
  categories?: Array<{ path: string; data: Record<string, unknown> }>;
  auditDataOverrides?: Record<string, unknown>;
}) {
  const auditId = 'audit-1';
  const templateRef = { id: 'tpl-1', path: 'templates/tpl-1' };
  const companyRef = { id: 'company-1', path: 'companies/company-1' };

  const writes: Array<{
    refPath: string;
    data: Record<string, unknown>;
    options: { merge: boolean };
  }> = [];
  const historyWrites: Array<{
    refPath: string;
    data: Record<string, unknown>;
    options: { merge: boolean };
  }> = [];

  const clientRef = {
    id: 'client-1',
    path: 'clients/client-1',
    collection: jest.fn((name: string) => {
      if (name !== 'score_history') throw new Error(`Unexpected client subcollection ${name}`);
      return {
        doc: jest.fn((id: string) => {
          if (id !== auditId) throw new Error(`Unexpected score_history doc id ${id}`);
          return { path: `clients/client-1/score_history/${id}` };
        })
      };
    })
  };

  const auditData = options.auditExists
    ? ({
        templateRef,
        clientRef,
        companyRef,
        status: 'in_progress',
        auditorRef: { id: options.auditorUid ?? 'auditor-1' },
        ...options.auditDataOverrides
      } as Record<string, unknown>)
    : undefined;

  const answersDocs = (options.answers ?? []).map((answer, idx) =>
    makeDoc(`audits/${auditId}/answers/a${idx + 1}`, answer)
  );
  const questionDocs = (options.questions ?? []).map((q) => makeDoc(q.path, q.data));
  const categoryDocs = (options.categories ?? []).map((c) => makeDoc(c.path, c.data));

  const auditRef = {
    id: auditId,
    path: `audits/${auditId}`,
    get: jest.fn(async () => ({
      exists: options.auditExists,
      data: () => auditData
    })),
    collection: jest.fn((name: string) => {
      if (name !== 'answers') throw new Error(`Unexpected audit subcollection ${name}`);
      return {
        get: jest.fn(async () => ({
          docs: answersDocs
        }))
      };
    })
  };

  const batch = {
    set: jest.fn((ref: { path?: string }, data: Record<string, unknown>, options: { merge: boolean }) => {
      const path = ref.path ?? '';
      if (path === `audits/${auditId}`) {
        writes.push({ refPath: path, data, options });
      } else if (path === `clients/client-1/score_history/${auditId}`) {
        historyWrites.push({ refPath: path, data, options });
      } else {
        throw new Error(`Unexpected batch set path ${path}`);
      }
    }),
    commit: jest.fn(async () => {})
  };

  const firestore = {
    batch: jest.fn(() => batch),
    collection: jest.fn((name: string) => {
      if (name === 'audits') {
        return {
          doc: jest.fn((id: string) => {
            if (id !== auditId) throw new Error('Unexpected audit id');
            return auditRef;
          })
        };
      }
      if (name === 'users') {
        return {
          doc: jest.fn(() => ({
            get: jest.fn(async () => ({
              data: () => ({ role: options.role ?? 'admin' })
            }))
          }))
        };
      }
      if (name === 'questions') {
        return {
          where: jest.fn(() => ({
            orderBy: jest.fn(() => ({
              get: jest.fn(async () => ({
                docs: questionDocs
              }))
            }))
          }))
        };
      }
      if (name === 'categories') {
        return {
          where: jest.fn(() => ({
            orderBy: jest.fn(() => ({
              get: jest.fn(async () => ({
                docs: categoryDocs
              }))
            }))
          }))
        };
      }
      throw new Error(`Unexpected collection ${name}`);
    })
  } as any;

  return { firestore, writes, historyWrites, auditId, clientRef, batch };
}

describe('computeAndPersistAuditScoreHandler', () => {
  const fixedNow = new Date('2026-03-03T12:00:00.000Z');

  it('persists score and upserts client score_history for authorized user', async () => {
    const { firestore, writes, historyWrites, auditId, clientRef, batch } = makeFirestoreMock({
      auditExists: true,
      role: 'admin',
      answers: [
        { questionRef: { path: 'questions/q1' }, response: 'compliant' },
        { questionRef: { path: 'questions/q2' }, response: 'non_compliant' },
        { questionRef: { path: 'questions/q3' }, response: 'not_observed' }
      ],
      questions: [
        {
          path: 'questions/q1',
          data: { categoryRef: { path: 'categories/c1' }, weight: 2, order: 1, text: 'Q1' }
        },
        {
          path: 'questions/q2',
          data: { categoryRef: { path: 'categories/c1' }, weight: 1, order: 2, text: 'Q2' }
        },
        {
          path: 'questions/q3',
          data: { categoryRef: { path: 'categories/c2' }, weight: 4, order: 1, text: 'Q3' }
        }
      ],
      categories: [
        { path: 'categories/c1', data: { name: 'Cat1', order: 1 } },
        { path: 'categories/c2', data: { name: 'Cat2', order: 2 } }
      ]
    });

    const result = await computeAndPersistAuditScoreHandler(
      { auth: { uid: 'u-admin' }, data: { auditId } },
      { firestore, now: () => fixedNow }
    );

    expect(result.auditId).toBe(auditId);
    expect(result.scoreFinal).toBe(66.7);
    expect(result.scoreByCategoryCount).toBe(2);
    expect(result.scoreVersion).toBe(1);
    expect(result.scoredAt).toBe('2026-03-03T12:00:00.000Z');

    expect(writes).toHaveLength(1);
    expect(writes[0].options).toEqual({ merge: true });
    expect(writes[0].refPath).toBe(`audits/${auditId}`);
    expect(writes[0].data.scoreFinal).toBe(66.7);
    expect(writes[0].data.scoreByCategory).toEqual({
      'categories/c1': 66.7,
      'categories/c2': 0
    });
    expect(writes[0].data.scoreVersion).toBe(1);
    expect(writes[0].data.scoredAt).toBeDefined();

    expect(historyWrites).toHaveLength(1);
    expect(historyWrites[0].options).toEqual({ merge: true });
    expect(historyWrites[0].refPath).toBe(`clients/client-1/score_history/${auditId}`);
    expect(historyWrites[0].data.auditId).toBe(auditId);
    expect(historyWrites[0].data.clientRef).toBe(clientRef);
    expect(historyWrites[0].data.scoreFinal).toBe(66.7);
    expect(historyWrites[0].data.scoreVersion).toBe(1);
    expect(historyWrites[0].data.updatedAt).toBeDefined();
    expect(batch.commit).toHaveBeenCalledTimes(1);
  });

  it('throws unauthenticated without auth', async () => {
    const { firestore, auditId } = makeFirestoreMock({ auditExists: true });

    await expect(
      computeAndPersistAuditScoreHandler(
        { auth: null, data: { auditId } },
        { firestore, now: () => fixedNow }
      )
    ).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  it('throws permission-denied for non-owner non-admin user', async () => {
    const { firestore, auditId } = makeFirestoreMock({
      auditExists: true,
      role: 'auditor',
      auditorUid: 'another-user'
    });

    await expect(
      computeAndPersistAuditScoreHandler(
        { auth: { uid: 'u-auditor' }, data: { auditId } },
        { firestore, now: () => fixedNow }
      )
    ).rejects.toMatchObject({ code: 'permission-denied' });
  });

  it('throws not-found for missing audit', async () => {
    const { firestore, auditId } = makeFirestoreMock({ auditExists: false });

    await expect(
      computeAndPersistAuditScoreHandler(
        { auth: { uid: 'u-admin' }, data: { auditId } },
        { firestore, now: () => fixedNow }
      )
    ).rejects.toMatchObject({ code: 'not-found' });
  });

  it('returns cached score without refetching answers when audit has not changed', async () => {
    const updatedAt = new Date('2026-03-03T10:00:00.000Z');
    const cachedScoredAt = new Date('2026-03-03T11:00:00.000Z');
    const { firestore, writes, historyWrites, auditId, batch } = makeFirestoreMock({
      auditExists: true,
      role: 'admin',
      auditDataOverrides: {
        updated_at: updatedAt,
        scoreComputedForUpdatedAt: updatedAt,
        scoreFinal: 91.2,
        scoreByCategory: {
          'categories/c1': 88.4
        },
        scoreVersion: 1,
        scoredAt: cachedScoredAt
      }
    });

    const result = await computeAndPersistAuditScoreHandler(
      { auth: { uid: 'u-admin' }, data: { auditId } },
      { firestore, now: () => fixedNow }
    );

    expect(result.auditId).toBe(auditId);
    expect(result.scoreFinal).toBe(91.2);
    expect(result.scoreByCategoryCount).toBe(1);
    expect(result.scoreVersion).toBe(1);
    expect(result.scoredAt).toBe('2026-03-03T11:00:00.000Z');
    expect(result.cached).toBe(true);
    expect(writes).toHaveLength(0);
    expect(historyWrites).toHaveLength(0);
    expect(batch.commit).not.toHaveBeenCalled();
  });
});
