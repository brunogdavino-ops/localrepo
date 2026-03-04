import { upsertClientScoreHistory } from './upsertClientScoreHistory';

describe('upsertClientScoreHistory', () => {
  it('writes to deterministic score_history doc id (idempotent path)', async () => {
    const setCalls: Array<{ data: Record<string, unknown>; options: { merge: boolean } }> = [];
    const historyRef = {
      set: jest.fn(async (data: Record<string, unknown>, options: { merge: boolean }) => {
        setCalls.push({ data, options });
      })
    };

    const clientRef = {
      id: 'client-1',
      path: 'clients/client-1',
      collection: jest.fn((name: string) => ({
        doc: jest.fn((id: string) => {
          if (name !== 'score_history') throw new Error('wrong subcollection');
          if (id !== 'audit-1') throw new Error('wrong doc id');
          return historyRef;
        })
      }))
    } as any;

    const firestore = {} as any;
    const params = {
      auditId: 'audit-1',
      auditRef: { id: 'audit-1', path: 'audits/audit-1' } as any,
      auditData: {
        clientRef,
        companyRef: { id: 'company-1', path: 'companies/company-1' },
        status: 'completed'
      } as Record<string, unknown>,
      scoreFinal: 92.3,
      scoreByCategory: { 'categories/c1': 92.3 },
      scoreVersion: 1
    };

    await upsertClientScoreHistory(params, { firestore });
    await upsertClientScoreHistory(params, { firestore });

    expect(clientRef.collection).toHaveBeenCalledWith('score_history');
    expect(setCalls).toHaveLength(2);
    expect(setCalls[0].options).toEqual({ merge: true });
    expect(setCalls[1].options).toEqual({ merge: true });
    expect(setCalls[0].data.auditId).toBe('audit-1');
    expect(setCalls[1].data.auditId).toBe('audit-1');
  });
});
