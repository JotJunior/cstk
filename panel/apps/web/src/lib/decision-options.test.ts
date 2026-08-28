/**
 * Testes da derivacao das opcoes de uma decisao e do match com a escolha.
 */
import { describe, it, expect } from 'vitest';
import { decisionOptions, chosenOptionIndex } from './decision-options.js';

describe('decisionOptions', () => {
  it('JSON array → um chip por item', () => {
    expect(decisionOptions('["haiku","sonnet","opus"]')).toEqual(['haiku', 'sonnet', 'opus']);
  });

  it('null/undefined/vazio/array vazio → []', () => {
    expect(decisionOptions(null)).toEqual([]);
    expect(decisionOptions(undefined)).toEqual([]);
    expect(decisionOptions('')).toEqual([]);
    expect(decisionOptions('[]')).toEqual([]);
  });

  it('texto nao-JSON (legado) → split por virgula', () => {
    expect(decisionOptions('a, b, c')).toEqual(['a', 'b', 'c']);
  });
});

describe('chosenOptionIndex', () => {
  it('match exato (case/espaco-insensitive)', () => {
    expect(chosenOptionIndex(['haiku', 'sonnet', 'opus'], 'sonnet')).toBe(1);
    expect(chosenOptionIndex(['haiku', ' Sonnet '], 'sonnet')).toBe(1);
  });

  it('escolha com prefixo de namespace casa pelo trecho apos ":"', () => {
    expect(chosenOptionIndex(['haiku', 'sonnet', 'opus'], 'model:sonnet')).toBe(1);
  });

  it('escolha que ELABORA a opcao escolhida casa por prefixo', () => {
    const opts = ['Go (stack sugerida)', 'Node.js/TypeScript', 'Rust'];
    expect(chosenOptionIndex(opts, 'Go')).toBe(0);

    const opts2 = ['MVP minimo: fetch + parse', 'MVP completo: multi-framework', 'MVP enxuto so para Storybook React'];
    expect(chosenOptionIndex(opts2, 'MVP enxuto so para Storybook React: fetch DESIGN.md + emitir Stories')).toBe(2);
  });

  it('escolha nula, opcao vazia ou nada casa → -1', () => {
    expect(chosenOptionIndex(['sonnet'], null)).toBe(-1);
    expect(chosenOptionIndex([], 'model:sonnet')).toBe(-1);
    expect(chosenOptionIndex(['haiku', 'opus'], 'model:sonnet')).toBe(-1);
  });

  it('prefixo so casa em fronteira de token (nao corta palavra)', () => {
    // "go" nao deve casar "golang" (proximo char e alfanumerico)
    expect(chosenOptionIndex(['golang', 'rust'], 'go')).toBe(-1);
  });

  it('match exato vence prefixo entre opcoes irmas', () => {
    const opts = ['MVP', 'MVP enxuto so para Storybook'];
    expect(chosenOptionIndex(opts, 'MVP')).toBe(0);
  });
});
