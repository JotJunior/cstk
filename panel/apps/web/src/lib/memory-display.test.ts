/**
 * Testes da derivacao defensiva de descricao de memorias.
 * Ref: memory-display.ts — cobre o caso real (description='---' por frontmatter).
 */
import { describe, it, expect } from 'vitest';
import { memoryDisplayDescription } from './memory-display.js';

const FRONTMATTER_MD = [
  '---',
  'name: feedback_code_in_english',
  'description: Codigo em ingles obrigatorio',
  'metadata:',
  '  type: feedback',
  '---',
  '',
  'Identificadores em ingles; comentarios podem ser pt.',
].join('\n');

describe('memoryDisplayDescription', () => {
  it('usa a description do produtor quando e prosa util', () => {
    const r = memoryDisplayDescription({
      slug: 's',
      description: 'Dashboard read-only de observabilidade',
      body: 'qualquer',
    });
    expect(r).toBe('Dashboard read-only de observabilidade');
  });

  it('caso real: description="---" cai para o campo description: do frontmatter', () => {
    const r = memoryDisplayDescription({
      slug: 'feedback_code_in_english',
      description: '---',
      body: FRONTMATTER_MD,
    });
    expect(r).toBe('Codigo em ingles obrigatorio');
  });

  it('description vazia tambem dispara o fallback', () => {
    const r = memoryDisplayDescription({
      slug: 'x',
      description: '',
      body: FRONTMATTER_MD,
    });
    expect(r).toBe('Codigo em ingles obrigatorio');
  });

  it('sem description: no frontmatter, usa a 1a linha de prosa (ignora heading)', () => {
    const body = ['---', 'name: foo', '---', '', '# Titulo', '', 'Primeira prosa real.'].join('\n');
    const r = memoryDisplayDescription({ slug: 'foo', description: '---', body });
    expect(r).toBe('Titulo'); // heading vira a 1a linha de prosa apos limpar '#'
  });

  it('1a linha de prosa quando nao ha heading nem description no frontmatter', () => {
    const body = ['---', 'name: foo', '---', '', 'Apenas prosa, sem heading.'].join('\n');
    const r = memoryDisplayDescription({ slug: 'foo', description: '---', body });
    expect(r).toBe('Apenas prosa, sem heading.');
  });

  it('corpo so com frontmatter/vazio cai para o slug humanizado', () => {
    const body = ['---', 'name: project_dashboard_panel', '---', ''].join('\n');
    const r = memoryDisplayDescription({ slug: 'project_dashboard_panel', description: '---', body });
    expect(r).toBe('project dashboard panel');
  });

  it('body nulo + description ruido cai para o slug humanizado', () => {
    const r = memoryDisplayDescription({ slug: 'feedback_test_path', description: '---', body: null });
    expect(r).toBe('feedback test path');
  });
});
