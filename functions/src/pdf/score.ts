import { DocumentReference, QueryDocumentSnapshot } from 'firebase-admin/firestore';

type DocRef = DocumentReference | null | undefined;

export type QuestionDoc = QueryDocumentSnapshot;
export type AnswerData = Record<string, unknown>;

export interface QuestionWithOrder {
  id: string;
  path: string;
  categoryPath: string;
  text: string;
  order: number;
  weight: number;
}

export interface OrderedCategorySection {
  id: string;
  path: string;
  name: string;
  order: number;
  questions: QuestionWithOrder[];
}

export function questionPathFromAnswer(answer: AnswerData): string | null {
  const questionRef = answer['questionRef'] as DocRef;
  return questionRef?.path ?? null;
}

export function responseFromAnswer(answer: AnswerData): string | null {
  const response = answer['response'] ?? answer['value'];
  return typeof response === 'string' ? response : null;
}

export function toQuestionsWithOrder(questions: QuestionDoc[]): QuestionWithOrder[] {
  return questions.map((question) => {
    const data = question.data();
    const categoryRef = data.categoryRef as DocRef;
    const orderValue = data.order;
    const weightValue = data.weight;

    return {
      id: question.id,
      path: question.ref.path,
      categoryPath: categoryRef?.path ?? 'sem-categoria',
      text: typeof data.text === 'string' && data.text.trim().length > 0
          ? data.text.trim()
          : 'Pergunta sem texto',
      order: typeof orderValue === 'number' ? orderValue : 999999,
      weight: typeof weightValue === 'number' ? weightValue : 1
    };
  });
}

export function mapAnswersByQuestionPath(answers: AnswerData[]): Map<string, AnswerData> {
  const map = new Map<string, AnswerData>();
  for (const answer of answers) {
    const path = questionPathFromAnswer(answer);
    if (path != null) {
      map.set(path, answer);
    }
  }
  return map;
}

export function calculateWeightedScore(answers: AnswerData[], questions: QuestionDoc[]): number {
  const questionsByPath = new Map<string, QuestionWithOrder>();
  for (const question of toQuestionsWithOrder(questions)) {
    questionsByPath.set(question.path, question);
  }

  let totalEvaluatedWeight = 0;
  let totalCompliantWeight = 0;

  for (const answer of answers) {
    const response = responseFromAnswer(answer);
    if (response !== 'compliant' && response !== 'non_compliant') continue;

    const questionPath = questionPathFromAnswer(answer);
    const weight = questionPath == null ? 1 : questionsByPath.get(questionPath)?.weight ?? 1;
    totalEvaluatedWeight += weight;
    if (response === 'compliant') {
      totalCompliantWeight += weight;
    }
  }

  if (totalEvaluatedWeight === 0) return 0;
  return Number(((totalCompliantWeight / totalEvaluatedWeight) * 100).toFixed(1));
}

export function calculateCategoryWeightedScore(
  categoryRefPath: string,
  questions: QuestionDoc[],
  answers: AnswerData[]
): number {
  const answersByQuestionPath = mapAnswersByQuestionPath(answers);
  let totalEvaluatedWeight = 0;
  let totalCompliantWeight = 0;

  for (const question of toQuestionsWithOrder(questions)) {
    if (question.categoryPath !== categoryRefPath) continue;
    const answer = answersByQuestionPath.get(question.path);
    if (!answer) continue;

    const response = responseFromAnswer(answer);
    if (response !== 'compliant' && response !== 'non_compliant') continue;

    totalEvaluatedWeight += question.weight;
    if (response === 'compliant') {
      totalCompliantWeight += question.weight;
    }
  }

  if (totalEvaluatedWeight === 0) return 0;
  return Number(((totalCompliantWeight / totalEvaluatedWeight) * 100).toFixed(1));
}

export function buildOrderedSections(
  categories: QueryDocumentSnapshot[],
  questions: QueryDocumentSnapshot[]
): OrderedCategorySection[] {
  const categoriesByPath = new Map<
    string,
    { id: string; path: string; name: string; order: number }
  >();

  for (const category of categories) {
    const data = category.data();
    categoriesByPath.set(category.ref.path, {
      id: category.id,
      path: category.ref.path,
      name: typeof data.name === 'string' && data.name.trim().length > 0
          ? data.name.trim()
          : 'Sem categoria',
      order: typeof data.order === 'number' ? data.order : 999999
    });
  }

  const grouped = new Map<string, QuestionWithOrder[]>();
  for (const question of toQuestionsWithOrder(questions)) {
    if (!grouped.has(question.categoryPath)) {
      grouped.set(question.categoryPath, []);
    }
    grouped.get(question.categoryPath)!.push(question);
  }

  const sections: OrderedCategorySection[] = [];
  for (const [categoryPath, categoryQuestions] of grouped.entries()) {
    categoryQuestions.sort((a, b) => a.order - b.order);
    const category = categoriesByPath.get(categoryPath) ?? {
      id: categoryPath,
      path: categoryPath,
      name: 'Sem categoria',
      order: 999999
    };
    sections.push({
      id: category.id,
      path: category.path,
      name: category.name,
      order: category.order,
      questions: categoryQuestions
    });
  }

  sections.sort((a, b) => a.order - b.order);
  return sections;
}
