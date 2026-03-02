import {
  buildOrderedSections,
  calculateCategoryWeightedScore,
  calculateWeightedScore
} from './score';

function makeDoc(path: string, data: Record<string, unknown>) {
  const parts = path.split('/');
  return {
    id: parts[parts.length - 1],
    ref: { path },
    data: () => data
  } as any;
}

describe('score helpers', () => {
  it('calculates weighted overall score', () => {
    const questions = [
      makeDoc('questions/q1', { categoryRef: { path: 'categories/c1' }, weight: 2, order: 2, text: 'Q1' }),
      makeDoc('questions/q2', { categoryRef: { path: 'categories/c1' }, weight: 1, order: 1, text: 'Q2' }),
      makeDoc('questions/q3', { categoryRef: { path: 'categories/c2' }, weight: 3, order: 1, text: 'Q3' })
    ];
    const answers = [
      { questionRef: { path: 'questions/q1' }, response: 'compliant' },
      { questionRef: { path: 'questions/q2' }, response: 'non_compliant' },
      { questionRef: { path: 'questions/q3' }, response: 'not_observed' }
    ];

    expect(calculateWeightedScore(answers, questions)).toBe(66.7);
  });

  it('calculates weighted score by category', () => {
    const questions = [
      makeDoc('questions/q1', { categoryRef: { path: 'categories/c1' }, weight: 2, order: 2, text: 'Q1' }),
      makeDoc('questions/q2', { categoryRef: { path: 'categories/c1' }, weight: 2, order: 1, text: 'Q2' }),
      makeDoc('questions/q3', { categoryRef: { path: 'categories/c2' }, weight: 1, order: 1, text: 'Q3' })
    ];
    const answers = [
      { questionRef: { path: 'questions/q1' }, response: 'compliant' },
      { questionRef: { path: 'questions/q2' }, response: 'non_compliant' },
      { questionRef: { path: 'questions/q3' }, response: 'compliant' }
    ];

    expect(calculateCategoryWeightedScore('categories/c1', questions, answers)).toBe(50.0);
    expect(calculateCategoryWeightedScore('categories/c2', questions, answers)).toBe(100.0);
  });

  it('builds ordered sections by category and question order', () => {
    const categories = [
      makeDoc('categories/c2', { name: 'B', order: 2 }),
      makeDoc('categories/c1', { name: 'A', order: 1 })
    ];
    const questions = [
      makeDoc('questions/q2', { categoryRef: { path: 'categories/c2' }, order: 2, text: 'QB2', weight: 1 }),
      makeDoc('questions/q1', { categoryRef: { path: 'categories/c1' }, order: 2, text: 'QA2', weight: 1 }),
      makeDoc('questions/q0', { categoryRef: { path: 'categories/c1' }, order: 1, text: 'QA1', weight: 1 })
    ];

    const sections = buildOrderedSections(categories, questions);
    expect(sections.map((s) => s.name)).toEqual(['A', 'B']);
    expect(sections[0].questions.map((q) => q.text)).toEqual(['QA1', 'QA2']);
  });
});
