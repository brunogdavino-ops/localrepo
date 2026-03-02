import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import path from 'node:path';

import {
  DocumentReference,
  QueryDocumentSnapshot,
  Timestamp,
  getFirestore
} from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import chromium from '@sparticuz/chromium';
import puppeteer from 'puppeteer-core';

import {
  AnswerData,
  buildOrderedSections,
  calculateCategoryWeightedScore,
  calculateWeightedScore,
  responseFromAnswer,
  toQuestionsWithOrder
} from './score';

const MAX_PHOTOS_PER_QUESTION = 3;
const TEMPLATE_FILE = path.resolve(__dirname, 'templates', 'audit-report.html');
const LOGO_FILE = path.resolve(__dirname, 'templates', 'logo-artezi.png');

type PhotoRecord = { path: string; fileName: string };
type NonComplianceItem = {
  order: number;
  questionText: string;
  status: string;
  comment: string;
  photos: string[];
};
type ChecklistItem = {
  order: number;
  description: string;
  status: string;
  statusClass: string;
};

function mapToHttpsError(error: unknown): HttpsError {
  if (error instanceof HttpsError) {
    return error;
  }

  const message = error instanceof Error ? error.message : String(error);

  if (message.includes('The query requires an index')) {
    return new HttpsError(
      'failed-precondition',
      'Consulta do Firestore requer indice composto.'
    );
  }

  if (message.includes('Permission') && message.includes('signBlob')) {
    return new HttpsError(
      'failed-precondition',
      'Permissao insuficiente para assinar URL de download do PDF.'
    );
  }

  if (
    message.includes('Failed to launch the browser process') ||
    message.includes('Could not find Chrome')
  ) {
    return new HttpsError(
      'failed-precondition',
      'Renderizador de PDF indisponivel no servidor.'
    );
  }

  if (message.includes('No such object')) {
    return new HttpsError('not-found', 'Arquivo de foto nao encontrado no Storage.');
  }

  return new HttpsError('internal', 'Falha interna ao gerar PDF.');
}

function asDate(value: unknown): Date | null {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

function datePtBr(date: Date | null): string {
  if (!date) return '--/--/----';
  return new Intl.DateTimeFormat('pt-BR').format(date);
}

function ptBrStatus(status: string): string {
  switch (status) {
    case 'in_progress':
      return 'Em andamento';
    case 'validation_pending':
      return 'Em Validação';
    case 'completed':
      return 'Concluída';
    default:
      return status || '-';
  }
}

function ptBrResponse(response: string | null): string {
  switch (response) {
    case 'compliant':
      return 'Adequado';
    case 'non_compliant':
      return 'Inadequado';
    case 'not_applicable':
      return 'Não se aplica';
    case 'not_observed':
      return 'Não observado';
    default:
      return '-';
  }
}

function scoreClass(score: number): { label: string; className: string } {
  if (score >= 85) return { label: 'Bom', className: 'status-good' };
  if (score >= 70) return { label: 'Regular', className: 'status-regular' };
  return { label: 'Crítico', className: 'status-bad' };
}

function responseClass(response: string | null): string {
  if (response === 'compliant') return 'status-good';
  if (response === 'non_compliant') return 'status-bad';
  return 'status-regular';
}

function assertCanAccessAudit(
  uid: string,
  userData: Record<string, unknown> | undefined,
  auditData: Record<string, unknown>
): void {
  const role = typeof userData?.['role'] === 'string' ? userData['role'] : '';
  const isAdmin = ['admin', 'owner', 'super_admin'].includes(String(role));
  const auditorRef = auditData['auditorRef'] as { id?: string } | undefined;
  const isOwnerAuditor = auditorRef?.id === uid;
  if (!isAdmin && !isOwnerAuditor) {
    throw new HttpsError('permission-denied', 'Sem permissao para exportar esta auditoria.');
  }
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

async function buildPdfFromHtml(html: string): Promise<Buffer> {
  const executablePath = await chromium.executablePath();
  const browser = await puppeteer.launch({
    headless: true,
    args: [...chromium.args, '--no-sandbox', '--disable-setuid-sandbox'],
    executablePath,
    defaultViewport: chromium.defaultViewport
  });

  try {
    const page = await browser.newPage();
    await page.setContent(html, { waitUntil: 'networkidle0' });
    const pdf = await page.pdf({
      format: 'A4',
      printBackground: true,
      margin: {
        top: '14mm',
        right: '10mm',
        bottom: '14mm',
        left: '10mm'
      }
    });
    return Buffer.from(pdf);
  } finally {
    await browser.close();
  }
}

function photoMime(pathValue: string): string {
  const lower = pathValue.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

async function photoDataUri(storagePath: string): Promise<string | null> {
  try {
    const [bytes] = await getStorage().bucket().file(storagePath).download();
    return `data:${photoMime(storagePath)};base64,${bytes.toString('base64')}`;
  } catch {
    return null;
  }
}

async function renderHtmlTemplate(input: {
  logoDataUri: string;
  clientName: string;
  auditCode: string;
  auditDate: string;
  auditorName: string;
  auditStatus: string;
  overallScore: number;
  categoryRows: string;
  nonComplianceRows: string;
  checklistRows: string;
}): Promise<string> {
  const template = await readFile(TEMPLATE_FILE, 'utf8');
  const replaceToken = (source: string, token: string, value: string): string =>
    source.split(token).join(value);

  let html = template;
  html = replaceToken(html, '{{LOGO_DATA_URI}}', input.logoDataUri);
  html = replaceToken(html, '{{CLIENT_NAME}}', escapeHtml(input.clientName));
  html = replaceToken(html, '{{AUDIT_CODE}}', escapeHtml(input.auditCode));
  html = replaceToken(html, '{{AUDIT_DATE}}', escapeHtml(input.auditDate));
  html = replaceToken(html, '{{AUDITOR_NAME}}', escapeHtml(input.auditorName));
  html = replaceToken(html, '{{AUDIT_STATUS}}', escapeHtml(input.auditStatus));
  html = replaceToken(html, '{{OVERALL_SCORE}}', input.overallScore.toFixed(1));
  html = replaceToken(html, '{{CATEGORY_ROWS}}', input.categoryRows);
  html = replaceToken(html, '{{NON_COMPLIANCE_ROWS}}', input.nonComplianceRows);
  html = replaceToken(html, '{{CHECKLIST_ROWS}}', input.checklistRows);
  return html;
}

export const generateAuditPdf = onCall(
  {
    memory: '1GiB',
    timeoutSeconds: 120
  },
  async (request) => {
  const startedAtMs = Date.now();
  const stageStart = new Map<string, number>();
  const markStage = (name: string): void => {
    stageStart.set(name, Date.now());
    console.info('[generateAuditPdf] stage:start', { stage: name });
  };
  const endStage = (name: string, extra?: Record<string, unknown>): void => {
    const start = stageStart.get(name);
    const elapsedMs = start == null ? null : Date.now() - start;
    console.info('[generateAuditPdf] stage:end', {
      stage: name,
      elapsedMs,
      ...extra
    });
  };

  try {
    markStage('start');
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Usuario nao autenticado.');
    }

    const auditId =
      typeof request.data?.auditId === 'string' ? request.data.auditId.trim() : '';
    if (!auditId) {
      throw new HttpsError('invalid-argument', 'auditId e obrigatorio.');
    }

    const firestore = getFirestore();
    const storage = getStorage();
    const uid = request.auth.uid;
    console.info('[generateAuditPdf] auth ok', { uid, auditId });
    endStage('start', { auditId, uid });

    markStage('fetch_audit');
    const auditRef = firestore.collection('audits').doc(auditId);
    const auditSnapshot = await auditRef.get();
    if (!auditSnapshot.exists) {
      throw new HttpsError('not-found', 'Auditoria nao encontrada.');
    }
    endStage('fetch_audit');

    markStage('authz');
    const auditData = (auditSnapshot.data() ?? {}) as Record<string, unknown>;
    const userSnapshot = await firestore.collection('users').doc(uid).get();
    const userData = userSnapshot.data() as Record<string, unknown> | undefined;
    assertCanAccessAudit(uid, userData, auditData);
    endStage('authz');

    const templateRef = auditData['templateRef'] as DocumentReference | undefined;
    if (!templateRef) {
      throw new HttpsError('failed-precondition', 'Auditoria sem templateRef.');
    }

    markStage('fetch_questions_categories_answers');
    const answersSnapshot = await auditRef.collection('answers').get();
    const [questionsSnapshot, categoriesSnapshot] = await Promise.all([
      firestore
        .collection('questions')
        .where('templateRef', '==', templateRef)
        .orderBy('order')
        .get(),
      firestore
        .collection('categories')
        .where('templateref', '==', templateRef)
        .orderBy('order')
        .get()
    ]);
    endStage('fetch_questions_categories_answers', {
      answers: answersSnapshot.size,
      questions: questionsSnapshot.size,
      categories: categoriesSnapshot.size
    });

    markStage('build_sections_scores');
    const answers = answersSnapshot.docs.map((doc) => doc.data() as AnswerData);
    const questions = questionsSnapshot.docs;
    const sections = buildOrderedSections(categoriesSnapshot.docs, questions);
    const overallScore = calculateWeightedScore(answers, questions);
    endStage('build_sections_scores');

    let clientName = 'Cliente sem nome';
    const clientRef = auditData['clientRef'] as DocumentReference | undefined;
    if (clientRef) {
      const clientSnapshot = await clientRef.get();
      const clientData = (clientSnapshot.data() ?? {}) as Record<string, unknown>;
      const name = clientData['name'];
      if (typeof name === 'string' && name.trim().length > 0) {
        clientName = name.trim();
      }
    }

    let auditorName = 'Nao informado';
    const auditorRef = auditData['auditorRef'] as DocumentReference | undefined;
    if (auditorRef) {
      const auditorSnapshot = await auditorRef.get();
      const auditorData = (auditorSnapshot.data() ?? {}) as Record<string, unknown>;
      const maybeName = auditorData['name'] ?? auditorData['displayName'] ?? auditorData['username'];
      if (typeof maybeName === 'string' && maybeName.trim().length > 0) {
        auditorName = maybeName.trim();
      }
    }

    const answerByQuestionPath = new Map<string, AnswerData>();
    for (const answer of answers) {
      const questionRef = answer['questionRef'] as DocumentReference | undefined;
      if (questionRef?.path) {
        answerByQuestionPath.set(questionRef.path, answer);
      }
    }

    markStage('load_photos');
    const photosByQuestionPath = new Map<string, PhotoRecord[]>();
    for (const answerDoc of answersSnapshot.docs) {
      const answerData = answerDoc.data() as AnswerData;
      const response = responseFromAnswer(answerData);
      if (response !== 'non_compliant') continue;
      const questionRef = answerData['questionRef'] as DocumentReference | undefined;
      if (!questionRef) continue;

      const photosSnapshot = await answerDoc.ref
        .collection('photos')
        .orderBy('createdAt', 'asc')
        .limit(MAX_PHOTOS_PER_QUESTION)
        .get();

      photosByQuestionPath.set(
        questionRef.path,
        photosSnapshot.docs
          .map((photo) => {
            const data = photo.data() as Record<string, unknown>;
            const pathValue = typeof data['path'] === 'string' ? data['path'] : '';
            if (!pathValue) return null;
            const fileName = typeof data['fileName'] === 'string' && data['fileName'].trim()
              ? data['fileName'].trim()
              : photo.id;
            return { path: pathValue, fileName };
          })
          .filter((item): item is PhotoRecord => item !== null)
      );
    }
    endStage('load_photos');

    const rawAuditNumber = auditData['auditnumber'];
    const auditNumber = typeof rawAuditNumber === 'number' ? rawAuditNumber : null;
    const auditCode =
      auditNumber == null ? `AUD-${auditId}` : `ART-${String(auditNumber).padStart(4, '0')}`;
    const startedAt = asDate(auditData['startedAt']);
    const status = typeof auditData['status'] === 'string' ? auditData['status'] : '';

    const categoryRows = sections
      .map((section) => {
        const score = calculateCategoryWeightedScore(section.path, questions, answers);
        const cls = scoreClass(score);
        return `<tr><td>${escapeHtml(section.name)}</td><td>${score.toFixed(1)}%</td><td class="${cls.className}">${cls.label}</td></tr>`;
      })
      .join('');

    const questionOrder = toQuestionsWithOrder(
      questions as QueryDocumentSnapshot[]
    ).sort((a, b) => a.order - b.order);

    const nonConformityItems: NonComplianceItem[] = [];
    const checklistItems: ChecklistItem[] = [];
    for (const question of questionOrder) {
      const answer = answerByQuestionPath.get(question.path);
      const response = responseFromAnswer(answer ?? {});
      const statusLabel = ptBrResponse(response);
      const statusCss = responseClass(response);

      checklistItems.push({
        order: question.order,
        description: question.text,
        status: statusLabel,
        statusClass: statusCss
      });

      if (response !== 'non_compliant') continue;
      const notesValue = answer?.['notes'] ?? answer?.['comment'] ?? '';
      const comment = typeof notesValue === 'string' && notesValue.trim().length > 0
        ? notesValue.trim()
        : 'Sem comentario.';
      const photos = photosByQuestionPath.get(question.path) ?? [];
      const photoUris = (
        await Promise.all(
          photos.slice(0, MAX_PHOTOS_PER_QUESTION).map((photo) => photoDataUri(photo.path))
        )
      ).filter((value): value is string => value != null);
      nonConformityItems.push({
        order: question.order,
        questionText: question.text,
        status: statusLabel,
        comment,
        photos: photoUris
      });
    }

    const nonComplianceRows =
      nonConformityItems.length === 0
        ? '<div class="empty-box">Nenhuma nao conformidade identificada.</div>'
        : nonConformityItems
            .map((item) => {
              const photosHtml =
                item.photos.length === 0
                  ? '<div class="photo-empty">Sem evidencia fotografica.</div>'
                  : item.photos
                      .map(
                        (photo) =>
                          `<div class="photo-item"><img src="${photo}" alt="Evidencia"/></div>`
                      )
                      .join('');
              return `<div class="nonconform">
                <h3>Questao ${item.order}</h3>
                <div class="field"><strong>Pergunta:</strong> <span>${escapeHtml(item.questionText)}</span></div>
                <div class="field"><strong>Status:</strong> <span class="status-bad">${escapeHtml(item.status)}</span></div>
                <div class="field"><strong>Comentario:</strong> <span>${escapeHtml(item.comment)}</span></div>
                <div class="field"><strong>Evidencias:</strong></div>
                <div class="photos">${photosHtml}</div>
              </div>`;
            })
            .join('');

    const checklistRows = checklistItems
      .map(
        (item) =>
          `<tr><td>${item.order}</td><td>${escapeHtml(item.description)}</td><td class="${item.statusClass}">${escapeHtml(item.status)}</td></tr>`
      )
      .join('');

    markStage('render_html');
    let logoDataUri = '';
    try {
      logoDataUri = `data:image/png;base64,${(await readFile(LOGO_FILE)).toString('base64')}`;
    } catch (error) {
      console.warn('[generateAuditPdf] logo ausente, seguindo sem logo', { error });
    }
    const html = await renderHtmlTemplate({
      logoDataUri,
      clientName,
      auditCode,
      auditDate: datePtBr(startedAt),
      auditorName,
      auditStatus: ptBrStatus(status),
      overallScore,
      categoryRows,
      nonComplianceRows,
      checklistRows
    });
    endStage('render_html');

    markStage('render_pdf');
    const pdfBuffer = await buildPdfFromHtml(html);
    endStage('render_pdf', { bytes: pdfBuffer.length });

    markStage('upload_storage');
    const timestamp = Date.now();
    const reportPath = `audit_reports/${auditId}/audit_${timestamp}.pdf`;
    const file = storage.bucket().file(reportPath);
    await file.save(pdfBuffer, {
      contentType: 'application/pdf',
      resumable: false,
      metadata: { cacheControl: 'private, max-age=300' }
    });
    endStage('upload_storage', { reportPath });

    markStage('signed_url');
    const expires = Date.now() + 60 * 60 * 1000;
    let url: string;
    let expiresAt: string;
    try {
      const [signedUrl] = await file.getSignedUrl({
        action: 'read',
        expires
      });
      url = signedUrl;
      expiresAt = new Date(expires).toISOString();
      endStage('signed_url');
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (!message.includes('signBlob')) {
        throw error;
      }
      const token = randomUUID();
      await file.setMetadata({
        metadata: { firebaseStorageDownloadTokens: token }
      });
      const encodedPath = encodeURIComponent(reportPath);
      url = `https://firebasestorage.googleapis.com/v0/b/${storage.bucket().name}/o/${encodedPath}?alt=media&token=${token}`;
      expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
      endStage('signed_url', { fallbackToken: true });
    }

    console.info('[generateAuditPdf] done', { totalElapsedMs: Date.now() - startedAtMs });
    return { url, path: reportPath, expiresAt };
  } catch (error) {
    console.error('[generateAuditPdf] falha', {
      totalElapsedMs: Date.now() - startedAtMs,
      error
    });
    throw mapToHttpsError(error);
  }
  }
);
