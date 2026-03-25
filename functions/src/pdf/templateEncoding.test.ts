import { readFileSync } from 'node:fs';
import path from 'node:path';

describe('audit-report template encoding', () => {
  it('keeps PT-BR accents in UTF-8', () => {
    const templatePath = path.resolve(__dirname, 'templates', 'audit-report.html');
    const html = readFileSync(templatePath, 'utf8');

    expect(html).toContain('Relatório de Auditoria Sanitária');
    expect(html).toContain('Não conformidades identificadas');
    expect(html).toContain('Conclusão técnica');
    expect(html).toContain('Classificação');
  });
});
