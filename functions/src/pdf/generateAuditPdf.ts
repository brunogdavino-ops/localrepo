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
import { chromium as playwrightChromium } from 'playwright-core';
import sharp from 'sharp';

import {
  AnswerData,
  buildOrderedSections,
  calculateCategoryWeightedScore,
  calculateWeightedScore,
  questionPathFromAnswer,
  responseFromAnswer,
  toQuestionsWithOrder
} from './score';

const MAX_PHOTOS_PER_QUESTION = 2;
const MAX_INPUT_PHOTO_BYTES = 12_000_000;
const IMAGE_MAX_WIDTH_PX = 1200;
const IMAGE_JPEG_QUALITY = 72;
const PHOTO_QUERY_CONCURRENCY = 8;
const PHOTO_DOWNLOAD_CONCURRENCY = 6;
const TEMPLATE_FILE = path.resolve(__dirname, 'templates', 'audit-report.html');
const ARTEZI_LOGO_FILE = path.resolve(__dirname, 'templates', 'logo-artezi.png');
const CLIENT_LOGO_FILE = path.resolve(__dirname, 'templates', 'logo-atac.png');
const FOOTER_LOGO_FILE = path.resolve(__dirname, 'templates', 'logo-escura.png');
const FONT_400_FILE = path.resolve(__dirname, 'templates', 'fonts', 'inter-400.woff2');
const FONT_500_FILE = path.resolve(__dirname, 'templates', 'fonts', 'inter-500.woff2');
const FONT_600_FILE = path.resolve(__dirname, 'templates', 'fonts', 'inter-600.woff2');
const FONT_700_FILE = path.resolve(__dirname, 'templates', 'fonts', 'inter-700.woff2');
const FONT_800_FILE = path.resolve(__dirname, 'templates', 'fonts', 'inter-800.woff2');
const PDF_CATEGORY_BAR_TRACK_COLOR = '#E3E3EC';
const PDF_ENCODING_SENTINEL = 'RELATÓRIO DE AUDITORIA SANITÁRIA';

type PhotoRecord = { path: string; fileName: string };
type NonComplianceItem = {
  order: number;
  categoryName: string;
  questionText: string;
  status: string;
  comment: string;
  responsible: string;
  photos: string[];
  failedPhotos: number;
};

type ChecklistItem = {
  order: number;
  categoryName: string;
  description: string;
  status: string;
  statusClass: string;
};

type QuestionPhotoStats = {
  uris: string[];
  failedCount: number;
};

type ProcessedPhotoResult = {
  uri: string | null;
  originalBytes: number;
  processedBytes: number;
};

function mapToHttpsError(error: unknown): HttpsError {
  if (error instanceof HttpsError) return error;

  const message = error instanceof Error ? error.message : String(error);

  if (message.includes('The query requires an index')) {
    return new HttpsError('failed-precondition', 'Consulta do Firestore requer índice composto.');
  }

  if (message.includes('Permission') && message.includes('signBlob')) {
    return new HttpsError(
      'failed-precondition',
      'Permissão insuficiente para assinar URL de download do PDF.'
    );
  }

  if (
    message.includes('Failed to launch the browser process') ||
    message.includes('Could not find Chrome')
  ) {
    return new HttpsError('failed-precondition', 'Renderizador de PDF indisponível no servidor.');
  }

  if (message.includes('Memory limit')) {
    return new HttpsError('failed-precondition', 'Limite de memória excedido durante geração do PDF.');
  }

  if (message.includes('No such object')) {
    return new HttpsError('not-found', 'Arquivo de foto não encontrado no Storage.');
  }

  return new HttpsError('internal', 'Falha interna ao gerar PDF.');
}

function asDate(value: unknown): Date | null {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) return parsed;
  }
  return null;
}

function datePtBr(date: Date | null): string {
  if (!date) return '-';
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
  if (response === 'not_applicable') return 'status-na';
  if (response === 'not_observed') return 'status-not-observed';
  return 'status-muted';
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
    throw new HttpsError('permission-denied', 'Sem permissão para exportar esta auditoria.');
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

function toDisplay(value: unknown): string {
  if (typeof value !== 'string') return '-';
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : '-';
}

function firstText(
  sources: Array<Record<string, unknown> | undefined>,
  keys: string[]
): string {
  for (const source of sources) {
    if (!source) continue;
    for (const key of keys) {
      const value = source[key];
      if (typeof value === 'string' && value.trim().length > 0) {
        return value.trim();
      }
    }
  }
  return '-';
}

function firstDateText(
  sources: Array<Record<string, unknown> | undefined>,
  keys: string[]
): string {
  for (const source of sources) {
    if (!source) continue;
    for (const key of keys) {
      const value = source[key];
      const dateValue = asDate(value);
      if (dateValue) return datePtBr(dateValue);
      if (typeof value === 'string' && value.trim().length > 0) return value.trim();
    }
  }
  return '-';
}

function boolFromUnknown(value: unknown): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    return normalized === 'true' || normalized === '1' || normalized === 'sim';
  }
  if (typeof value === 'number') return value !== 0;
  return false;
}

function weightedScore(compliantWeight: number, evaluatedWeight: number): number {
  if (evaluatedWeight <= 0) return 0;
  return Number(((compliantWeight / evaluatedWeight) * 100).toFixed(1));
}

function calculateResponsibleScores(
  answers: AnswerData[],
  questions: QueryDocumentSnapshot[],
  operatorQuestionPaths: Set<string>
): { operatorScore: number; clientScore: number } {
  const questionsByPath = new Map(
    toQuestionsWithOrder(questions).map((question) => [question.path, question])
  );

  let operatorEvaluatedWeight = 0;
  let operatorCompliantWeight = 0;
  let clientEvaluatedWeight = 0;
  let clientCompliantWeight = 0;

  for (const answer of answers) {
    const response = responseFromAnswer(answer);
    if (response !== 'compliant' && response !== 'non_compliant') continue;

    const questionPath = questionPathFromAnswer(answer);
    const questionWeight = questionPath == null ? 1 : (questionsByPath.get(questionPath)?.weight ?? 1);
    const belongsToOperator = questionPath != null && operatorQuestionPaths.has(questionPath);

    if (belongsToOperator) {
      operatorEvaluatedWeight += questionWeight;
      if (response === 'compliant') operatorCompliantWeight += questionWeight;
    } else {
      clientEvaluatedWeight += questionWeight;
      if (response === 'compliant') clientCompliantWeight += questionWeight;
    }
  }

  return {
    operatorScore: weightedScore(operatorCompliantWeight, operatorEvaluatedWeight),
    clientScore: weightedScore(clientCompliantWeight, clientEvaluatedWeight)
  };
}

function buildScoreBars(items: Array<{ name: string; score: number }>): string {
  return items
    .map((item) => {
      const score = Number(item.score.toFixed(1));
      const cls = score >= 80 ? 'bar-good' : 'bar-bad';
      return `<div class="category-bar-row">
        <div class="category-bar-head">
          <span class="category-name">${escapeHtml(item.name)}</span>
          <span class="category-value">${score.toFixed(1)}%</span>
        </div>
        <div class="bar-track">
          <div class="bar-fill ${cls}" style="width:${Math.max(0, Math.min(100, score)).toFixed(1)}%"></div>
        </div>
      </div>`;
    })
    .join('');
}

async function buildPdfFromHtml(html: string): Promise<Buffer> {
  const normalizedHtml = html.toUpperCase();
  if (!normalizedHtml.includes(PDF_ENCODING_SENTINEL)) {
    console.error('[generateAuditPdf] encoding sentinel inválido', {
      expected: PDF_ENCODING_SENTINEL
    });
    throw new Error('Template HTML com encoding inválido (UTF-8 corrompido).');
  }

  const executablePath = await chromium.executablePath();
  const browser = await playwrightChromium.launch({
    executablePath,
    headless: true,
    args: [...chromium.args, '--no-sandbox', '--disable-setuid-sandbox']
  });

  try {
    const page = await browser.newPage({ viewport: chromium.defaultViewport });
    await page.setContent(html, { waitUntil: 'networkidle' });
    const pdf = await page.pdf({
      format: 'A4',
      printBackground: true,
      preferCSSPageSize: true,
      margin: { top: '0', right: '0', bottom: '0', left: '0' }
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

async function photoDataUri(storagePath: string): Promise<ProcessedPhotoResult> {
  try {
    const file = getStorage().bucket().file(storagePath);
    const [metadata] = await file.getMetadata();
    const metadataBytes = Number(metadata.size ?? 0);
    if (Number.isFinite(metadataBytes) && metadataBytes > MAX_INPUT_PHOTO_BYTES) {
      return {
        uri: null,
        originalBytes: metadataBytes,
        processedBytes: 0
      };
    }

    const [buffer] = await file.download();
    const originalBytes = buffer.length;
    const mime = photoMime(storagePath);
    const lowerPath = storagePath.toLowerCase();
    const isPng = lowerPath.endsWith('.png');

    let optimizedBuffer: Buffer = buffer;
    let outputMime = mime;
    try {
      const transformed = await sharp(buffer, { failOn: 'none' })
        .rotate()
        .resize({
          width: IMAGE_MAX_WIDTH_PX,
          withoutEnlargement: true,
          fit: 'inside'
        })
        .jpeg({
          quality: IMAGE_JPEG_QUALITY,
          mozjpeg: true,
          chromaSubsampling: '4:2:0'
        })
        .toBuffer();

      // Keep PNG only when it is materially smaller than optimized JPEG.
      if (isPng && buffer.length + 2048 < transformed.length) {
        optimizedBuffer = buffer;
        outputMime = 'image/png';
      } else {
        optimizedBuffer = transformed;
        outputMime = 'image/jpeg';
      }
    } catch {
      optimizedBuffer = buffer;
      outputMime = mime;
    }

    return {
      uri: `data:${outputMime};base64,${optimizedBuffer.toString('base64')}`,
      originalBytes,
      processedBytes: optimizedBuffer.length
    };
  } catch {
    return {
      uri: null,
      originalBytes: 0,
      processedBytes: 0
    };
  }
}

async function base64OrEmpty(filePath: string, label: string): Promise<string> {
  try {
    return (await readFile(filePath)).toString('base64');
  } catch (error) {
    console.warn('[generateAuditPdf] asset ausente, usando fallback', { label, filePath, error });
    return '';
  }
}

async function fontBase64OrEmpty(filePath: string): Promise<string> {
  try {
    return await readFile(filePath, 'base64');
  } catch (error) {
    console.warn('[generateAuditPdf] fonte ausente, usando fallback local()', { filePath, error });
    return '';
  }
}

async function mapWithConcurrency<T>(
  items: T[],
  concurrency: number,
  worker: (item: T) => Promise<void>
): Promise<void> {
  if (items.length === 0) return;
  const size = Math.max(1, concurrency);
  let cursor = 0;
  const runners = Array.from({ length: Math.min(size, items.length) }, async () => {
    while (true) {
      const index = cursor++;
      if (index >= items.length) break;
      await worker(items[index]);
    }
  });
  await Promise.all(runners);
}

async function renderHtmlTemplate(input: {
  arteziLogoDataUri: string;
  clientLogoDataUri: string;
  footerLogoDataUri: string;
  inter400: string;
  inter500: string;
  inter600: string;
  inter700: string;
  inter800: string;
  clientName: string;
  auditDate: string;
  auditAddress: string;
  operatorName: string;
  auditorName: string;
  openingDate: string;
  auditCode: string;
  issuedAt: string;
  overallScore: number;
  overallClassification: string;
  totalEvaluatedItems: number;
  nonCompliantCount: number;
  categoryBarTrackColor: string;
  categoryBars: string;
  responsibleBars: string;
  nonComplianceRows: string;
  checklistRows: string;
}): Promise<string> {
  const template = await readFile(TEMPLATE_FILE, 'utf8');
  const replaceToken = (source: string, token: string, value: string): string =>
    source.split(token).join(value);

  let html = template;
  html = replaceToken(html, '{{ARTEZI_LOGO_DATA_URI}}', input.arteziLogoDataUri);
  html = replaceToken(html, '{{CLIENT_LOGO_DATA_URI}}', input.clientLogoDataUri);
  html = replaceToken(html, '{{FOOTER_LOGO_DATA_URI}}', input.footerLogoDataUri);
  html = replaceToken(html, '{{INTER_400_WOFF2}}', input.inter400);
  html = replaceToken(html, '{{INTER_500_WOFF2}}', input.inter500);
  html = replaceToken(html, '{{INTER_600_WOFF2}}', input.inter600);
  html = replaceToken(html, '{{INTER_700_WOFF2}}', input.inter700);
  html = replaceToken(html, '{{INTER_800_WOFF2}}', input.inter800);
  html = replaceToken(html, '{{CLIENT_NAME}}', escapeHtml(input.clientName));
  html = replaceToken(html, '{{AUDIT_DATE}}', escapeHtml(input.auditDate));
  html = replaceToken(html, '{{AUDIT_ADDRESS}}', escapeHtml(input.auditAddress));
  html = replaceToken(html, '{{OPERATOR_NAME}}', escapeHtml(input.operatorName));
  html = replaceToken(html, '{{AUDITOR_NAME}}', escapeHtml(input.auditorName));
  html = replaceToken(html, '{{OPENING_DATE}}', escapeHtml(input.openingDate));
  html = replaceToken(html, '{{AUDIT_CODE}}', escapeHtml(input.auditCode));
  html = replaceToken(html, '{{ISSUED_AT}}', escapeHtml(input.issuedAt));
  html = replaceToken(html, '{{OVERALL_SCORE}}', input.overallScore.toFixed(1));
  html = replaceToken(html, '{{OVERALL_CLASSIFICATION}}', escapeHtml(input.overallClassification));
  html = replaceToken(html, '{{TOTAL_EVALUATED_ITEMS}}', String(input.totalEvaluatedItems));
  html = replaceToken(html, '{{NON_COMPLIANT_COUNT}}', String(input.nonCompliantCount));
  html = replaceToken(html, '{{CATEGORY_BAR_TRACK_COLOR}}', input.categoryBarTrackColor);
  html = replaceToken(html, '{{CATEGORY_BARS}}', input.categoryBars);
  html = replaceToken(html, '{{RESPONSIBLE_BARS}}', input.responsibleBars);
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
        throw new HttpsError('unauthenticated', 'Usuário não autenticado.');
      }

      const auditId =
        typeof request.data?.auditId === 'string' ? request.data.auditId.trim() : '';
      if (!auditId) {
        throw new HttpsError('invalid-argument', 'auditId é obrigatório.');
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
        throw new HttpsError('not-found', 'Auditoria não encontrada.');
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

      const fetchFirestoreStartMs = Date.now();
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

      let clientData: Record<string, unknown> | undefined;
      let clientName = '-';
      let operatorName = '-';
      const operatorQuestionPaths = new Set<string>();
      const clientRef = auditData['clientRef'] as DocumentReference | undefined;
      if (clientRef) {
        const clientSnapshot = await clientRef.get();
        clientData = (clientSnapshot.data() ?? {}) as Record<string, unknown>;
        clientName = firstText([clientData], ['name', 'clientName', 'razaoSocial']);

        const hasOperator = boolFromUnknown(clientData['hasOperator']);
        operatorName = hasOperator
          ? firstText([clientData], ['operatorName', 'operator'])
          : '-';

        const responsibilityMap =
          (clientData['responsibilityMap'] as Record<string, unknown> | undefined) ?? {};
        for (const [questionPath, owner] of Object.entries(responsibilityMap)) {
          if (typeof questionPath !== 'string' || questionPath.trim().length === 0) continue;
          if (owner === 'operator') {
            operatorQuestionPaths.add(questionPath);
          }
        }
      }

      let auditorData: Record<string, unknown> | undefined;
      let auditorName = '-';
      const auditorRef = auditData['auditorRef'] as DocumentReference | undefined;
      if (auditorRef) {
        const auditorSnapshot = await auditorRef.get();
        auditorData = (auditorSnapshot.data() ?? {}) as Record<string, unknown>;
        auditorName = firstText([auditorData], ['name', 'displayName', 'username']);
      }

      const answerByQuestionPath = new Map<string, AnswerData>();
      for (const answer of answers) {
        const questionRef = answer['questionRef'] as DocumentReference | undefined;
        if (questionRef?.path) {
          answerByQuestionPath.set(questionRef.path, answer);
        }
      }

      const nonCompliantCount = answers.filter(
        (answer) => responseFromAnswer(answer) === 'non_compliant'
      ).length;
      const totalEvaluatedItems = answers.filter((answer) => {
        const response = responseFromAnswer(answer);
        return response === 'compliant' || response === 'non_compliant';
      }).length;

      const imageDownloadStartMs = Date.now();
      markStage('load_photos');
      const photosByQuestionPath = new Map<string, PhotoRecord[]>();
      const nonCompliantAnswerDocs = answersSnapshot.docs.filter((answerDoc) => {
        const answerData = answerDoc.data() as AnswerData;
        const response = responseFromAnswer(answerData);
        return response === 'non_compliant';
      });
      await mapWithConcurrency(
        nonCompliantAnswerDocs,
        PHOTO_QUERY_CONCURRENCY,
        async (answerDoc) => {
          const answerData = answerDoc.data() as AnswerData;
          const questionRef = answerData['questionRef'] as DocumentReference | undefined;
          if (!questionRef) return;

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
                const fileName =
                  typeof data['fileName'] === 'string' && data['fileName'].trim()
                    ? data['fileName'].trim()
                    : photo.id;
                return { path: pathValue, fileName };
              })
              .filter((item): item is PhotoRecord => item !== null)
          );
        }
      );
      endStage('load_photos');
      const fetchFirestoreMs = Date.now() - fetchFirestoreStartMs;

      const rawAuditNumber = auditData['auditnumber'];
      const auditNumber = typeof rawAuditNumber === 'number' ? rawAuditNumber : null;
      const auditCode =
        auditNumber == null ? `AUD-${auditId}` : `ART-${String(auditNumber).padStart(4, '0')}`;
      const startedAt = asDate(auditData['startedAt']);
      const status = typeof auditData['status'] === 'string' ? auditData['status'] : '';

      const categoryBars = buildScoreBars(
        sections
          .map((section) => ({
            name: section.name,
            score: calculateCategoryWeightedScore(section.path, questions, answers)
          }))
          .sort((a, b) => a.score - b.score)
      );
      const responsibleScores = calculateResponsibleScores(
        answers,
        questions,
        operatorQuestionPaths
      );
      const responsibleBars = buildScoreBars([
        { name: 'Operador', score: responsibleScores.operatorScore },
        { name: 'Cliente', score: responsibleScores.clientScore }
      ]);

      const sectionByPath = new Map(sections.map((section) => [section.path, section]));
      const questionOrder = toQuestionsWithOrder(
        questions as QueryDocumentSnapshot[]
      ).sort((a, b) => a.order - b.order);

      const questionPhotoStats = new Map<string, QuestionPhotoStats>();
      const photoDownloadQueue: Array<{ questionPath: string; storagePath: string }> = [];
      let originalImagesTotalBytes = 0;
      let processedImagesTotalBytes = 0;
      for (const [questionPath, photoRecords] of photosByQuestionPath.entries()) {
        questionPhotoStats.set(questionPath, { uris: [], failedCount: 0 });
        const seenStoragePaths = new Set<string>();
        for (const photo of photoRecords) {
          if (seenStoragePaths.has(photo.path)) continue;
          seenStoragePaths.add(photo.path);
          photoDownloadQueue.push({ questionPath, storagePath: photo.path });
        }
      }
      await mapWithConcurrency(
        photoDownloadQueue,
        PHOTO_DOWNLOAD_CONCURRENCY,
        async ({ questionPath, storagePath }) => {
          const stats = questionPhotoStats.get(questionPath);
          if (!stats) return;
          const photo = await photoDataUri(storagePath);
          originalImagesTotalBytes += photo.originalBytes;
          processedImagesTotalBytes += photo.processedBytes;
          if (photo.uri == null) {
            stats.failedCount += 1;
          } else {
            stats.uris.push(photo.uri);
          }
        }
      );

      const nonConformityItems: NonComplianceItem[] = [];
      const checklistItems: ChecklistItem[] = [];
      for (const question of questionOrder) {
        const answer = answerByQuestionPath.get(question.path);
        const response = responseFromAnswer(answer ?? {});
        const statusLabel = ptBrResponse(response);
        const statusCss = responseClass(response);

        checklistItems.push({
          order: question.order,
          categoryName: sectionByPath.get(question.categoryPath)?.name ?? '-',
          description: question.text,
          status: statusLabel,
          statusClass: statusCss
        });

        if (response !== 'non_compliant') continue;
        const notesValue = answer?.['notes'] ?? answer?.['comment'] ?? '';
        const comment =
          typeof notesValue === 'string' && notesValue.trim().length > 0
            ? notesValue.trim()
            : 'Sem comentário.';
        const photoStats = questionPhotoStats.get(question.path);
        const photoUris = photoStats?.uris ?? [];
        const failedPhotos = photoStats?.failedCount ?? 0;
        const categoryName = sectionByPath.get(question.categoryPath)?.name ?? 'Sem categoria';

        nonConformityItems.push({
          order: question.order,
          categoryName,
          questionText: question.text,
          status: statusLabel,
          comment,
          responsible: 'N/A',
          photos: photoUris,
          failedPhotos
        });
      }
      const imageDownloadMs = Date.now() - imageDownloadStartMs;

      const nonComplianceRows =
        nonConformityItems.length === 0
          ? '<div class="empty-box">Nenhuma não conformidade identificada.</div>'
          : nonConformityItems
              .map((item) => {
                const photosHtml =
                  item.photos.length === 0 && item.failedPhotos === 0
                    ? '<div class="photo-empty">Sem evidência fotográfica.</div>'
                    : [
                        ...item.photos.map(
                          (photo) =>
                            `<div class="photo-item"><img src="${photo}" alt="Evidência" /></div>`
                        ),
                        ...Array.from(
                          { length: item.failedPhotos },
                          () => '<div class="photo-empty">Foto indisponível.</div>'
                        )
                      ].join('');
                return `<div class="nonconform">
                  <h3>Categoria: ${escapeHtml(item.categoryName)} - Questão ${item.order}</h3>
                  <div class="label">Descrição da Pergunta:</div>
                  <div class="value">${escapeHtml(item.questionText)}</div>
                  <div class="label">Responsável:</div>
                  <div class="value">${escapeHtml(item.responsible)}</div>
                  <div class="label">Descrição da Auditora:</div>
                  <div class="value">${escapeHtml(item.comment)}</div>
                  <div class="label">Evidências Fotográficas:</div>
                  <div class="photos">${photosHtml}</div>
                </div>`;
              })
              .join('');

      const checklistRows = checklistItems
        .map(
          (item) =>
            `<tr><td>${item.order}</td><td>${escapeHtml(item.categoryName)}</td><td>${escapeHtml(item.description)}</td><td class="${item.statusClass}">${escapeHtml(item.status)}</td></tr>`
        )
        .join('');

      const renderHtmlStartMs = Date.now();
      markStage('render_html');
      const [arteziLogoDataUri, clientLogoDataUri, footerLogoDataUri] = await Promise.all([
        base64OrEmpty(ARTEZI_LOGO_FILE, 'artezi-logo').then((b64) =>
          b64 ? `data:image/png;base64,${b64}` : ''
        ),
        base64OrEmpty(CLIENT_LOGO_FILE, 'client-logo').then((b64) =>
          b64 ? `data:image/png;base64,${b64}` : ''
        ),
        base64OrEmpty(FOOTER_LOGO_FILE, 'footer-logo').then((b64) =>
          b64 ? `data:image/png;base64,${b64}` : ''
        )
      ]);
      const [inter400, inter500, inter600, inter700, inter800] = await Promise.all([
        fontBase64OrEmpty(FONT_400_FILE),
        fontBase64OrEmpty(FONT_500_FILE),
        fontBase64OrEmpty(FONT_600_FILE),
        fontBase64OrEmpty(FONT_700_FILE),
        fontBase64OrEmpty(FONT_800_FILE)
      ]);

      const auditAddress = firstText([auditData, clientData], [
        'address',
        'auditAddress',
        'endereco'
      ]);
      const openingDate = firstDateText([clientData], [
        'inauguration',
        'inaugurationDate',
        'openingDate',
        'openedAt'
      ]);
      const overallClassification = scoreClass(overallScore).label.toUpperCase();

      const html = await renderHtmlTemplate({
        arteziLogoDataUri,
        clientLogoDataUri,
        footerLogoDataUri,
        inter400,
        inter500,
        inter600,
        inter700,
        inter800,
        clientName: toDisplay(clientName),
        auditDate: datePtBr(startedAt),
        auditAddress: toDisplay(auditAddress),
        operatorName: toDisplay(operatorName),
        auditorName: toDisplay(auditorName),
        openingDate: toDisplay(openingDate),
        auditCode: toDisplay(auditCode),
        issuedAt: datePtBr(new Date()),
        overallScore,
        overallClassification,
        totalEvaluatedItems,
        nonCompliantCount,
        categoryBarTrackColor: PDF_CATEGORY_BAR_TRACK_COLOR,
        categoryBars,
        responsibleBars,
        nonComplianceRows,
        checklistRows
      });
      endStage('render_html');
      const renderHtmlMs = Date.now() - renderHtmlStartMs;

      markStage('render_pdf');
      const renderPdfStartMs = Date.now();
      const pdfBuffer = await buildPdfFromHtml(html);
      endStage('render_pdf', { bytes: pdfBuffer.length });
      const renderPdfMs = Date.now() - renderPdfStartMs;

      markStage('upload_storage');
      const uploadStartMs = Date.now();
      const timestamp = Date.now();
      const reportPath = `audit_reports/${auditId}/audit_${timestamp}.pdf`;
      const file = storage.bucket().file(reportPath);
      await file.save(pdfBuffer, {
        contentType: 'application/pdf',
        resumable: false,
        metadata: { cacheControl: 'private, max-age=300' }
      });
      endStage('upload_storage', { reportPath });
      const uploadStorageMs = Date.now() - uploadStartMs;

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

      const totalElapsedMs = Date.now() - startedAtMs;
      const pdfSizeBytes = pdfBuffer.length;
      console.info('[generateAuditPdf] perf', {
        fetchFirestoreMs,
        originalImagesTotalBytes,
        processedImagesTotalBytes,
        imageDownloadMs,
        renderHtmlMs,
        renderPdfMs,
        uploadStorageMs,
        totalElapsedMs,
        pdfSizeBytes
      });
      console.info('[generateAuditPdf] done', { totalElapsedMs });
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
