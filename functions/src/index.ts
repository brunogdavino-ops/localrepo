import { initializeApp } from 'firebase-admin/app';

import { generateAuditPdf } from './pdf/generateAuditPdf';
import { backfillClientScoreHistory } from './score/backfillClientScoreHistory';
import { computeAndPersistAuditScore } from './score/computeAndPersistAuditScore';

initializeApp();

export { generateAuditPdf, computeAndPersistAuditScore, backfillClientScoreHistory };
