import { backfillClientScoreHistoryHandler } from './backfillClientScoreHistory';

function makeAuditDoc(id: string, data: Record<string, unknown>) {
  return {
    id,
    data: () => data
  } as any;
}

function makeFirestoreForBackfill(options?: { role?: string }) {
  const processed: string[] = [];
  const audits = [
    makeAuditDoc('a1', {
      templateRef: { id: 't1', path: 'templates/t1' },
      clientRef: {
        id: 'c1',
        path: 'clients/c1',
        collection: () => ({ doc: (id: string) => ({ path: `clients/c1/score_history/${id}` }) })
      },
      auditorRef: { id: 'aud-1' },
      status: 'in_progress'
    }),
    makeAuditDoc('a2', {
      templateRef: { id: 't1', path: 'templates/t1' },
      clientRef: {
        id: 'c2',
        path: 'clients/c2',
        collection: () => ({ doc: (id: string) => ({ path: `clients/c2/score_history/${id}` }) })
      },
      auditorRef: { id: 'aud-2' },
      status: 'completed'
    })
  ];

  const auditRefById: Record<string, any> = {};
  for (const audit of audits) {
    auditRefById[audit.id] = {
      id: audit.id,
      path: `audits/${audit.id}`,
      get: jest.fn(async () => ({ exists: true, data: audit.data })),
      collection: jest.fn((name: string) => {
        if (name !== 'answers') throw new Error('unexpected subcollection');
        return {
          get: jest.fn(async () => ({
            docs: [
              {
                data: () => ({ questionRef: { path: 'questions/q1' }, response: 'compliant' })
              }
            ]
          }))
        };
      })
    };
  }

  const firestore = {
    batch: jest.fn(() => ({
      set: jest.fn(),
      commit: jest.fn(async () => {})
    })),
    collection: jest.fn((name: string) => {
      if (name === 'users') {
        return {
          doc: jest.fn(() => ({
            get: jest.fn(async () => ({
              data: () => ({ role: options?.role ?? 'admin' })
            }))
          }))
        };
      }
      if (name === 'audits') {
        return {
          orderBy: jest.fn(() => ({
            limit: jest.fn(() => ({
              startAfter: jest.fn(() => ({
                get: jest.fn(async () => ({ empty: true, docs: [] }))
              })),
              get: jest.fn(async () => {
                if (processed.length > 0) {
                  return { empty: true, docs: [], size: 0 };
                }
                processed.push('page1');
                return { empty: false, docs: audits, size: audits.length };
              })
            }))
          })),
          doc: jest.fn((id: string) => auditRefById[id])
        };
      }
      if (name === 'questions') {
        return {
          where: jest.fn(() => ({
            orderBy: jest.fn(() => ({
              get: jest.fn(async () => ({
                docs: [
                  {
                    ref: { path: 'questions/q1' },
                    data: () => ({
                      text: 'Q1',
                      categoryRef: { path: 'categories/c1' },
                      order: 1,
                      weight: 1
                    })
                  }
                ]
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
                docs: [
                  {
                    id: 'c1',
                    ref: { path: 'categories/c1' },
                    data: () => ({ name: 'Cat1', order: 1 })
                  }
                ]
              }))
            }))
          }))
        };
      }
      throw new Error(`Unexpected collection ${name}`);
    })
  } as any;

  return { firestore };
}

describe('backfillClientScoreHistoryHandler', () => {
  it('processes audits in batch for admin user', async () => {
    const { firestore } = makeFirestoreForBackfill({ role: 'admin' });
    const result = await backfillClientScoreHistoryHandler(
      { auth: { uid: 'admin-1' }, data: { pageSize: 10 } },
      { firestore }
    );

    expect(result.processedCount).toBe(2);
    expect(result.successCount).toBe(2);
    expect(result.errorCount).toBe(0);
  });

  it('rejects unauthenticated calls', async () => {
    const { firestore } = makeFirestoreForBackfill({ role: 'admin' });
    await expect(
      backfillClientScoreHistoryHandler({ auth: null, data: {} }, { firestore })
    ).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  it('rejects non admin roles', async () => {
    const { firestore } = makeFirestoreForBackfill({ role: 'auditor' });
    await expect(
      backfillClientScoreHistoryHandler({ auth: { uid: 'u1' }, data: {} }, { firestore })
    ).rejects.toMatchObject({ code: 'permission-denied' });
  });
});
