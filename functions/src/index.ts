import { initializeApp } from 'firebase-admin/app';

import { generateAuditPdf } from './pdf/generateAuditPdf';

initializeApp();

export { generateAuditPdf };
