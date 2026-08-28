import { describe, it, expect } from 'vitest';
import { truncateBars, TRUNCATE_BARS_LIMIT, OTHERS_LABEL } from './truncate-bars.js';
import type { TruncatedBar } from './truncate-bars.js';

// Gera N barras ja ordenadas por volume desc (valor decrescente = volume desc).
function makeBars(n: number): TruncatedBar[] {
  return Array.from({ length: n }, (_, i) => ({ label: `etapa-${i + 1}`, value: n - i }));
}

describe('truncateBars', () => {
  it('14 etapas: 10 nomeadas + 1 barra Outros somando as 4 restantes (quickstart Cenario 5)', () => {
    const input = makeBars(14);
    const result = truncateBars(input);
    expect(result.bars.length).toBe(11);
    expect(result.bars.slice(0, 10).map(b => b.label)).toEqual(input.slice(0, 10).map(b => b.label));
    expect(result.othersLabel).toBe(OTHERS_LABEL);
    expect(result.bars[10]?.label).toBe(OTHERS_LABEL);
    // valores das etapas 11..14: 3+2+1... na convencao makeBars(14) values 14..1
    const expectedOthersValue = input.slice(10).reduce((s, b) => s + b.value, 0);
    expect(result.bars[10]?.value).toBe(expectedOthersValue);
    expect(result.othersMembers).toEqual(input.slice(10).map(b => b.label));
  });

  it('exatamente 10 etapas: 10 barras nomeadas, nenhuma barra Outros', () => {
    const input = makeBars(10);
    const result = truncateBars(input);
    expect(result.bars.length).toBe(10);
    expect(result.othersLabel).toBeNull();
    expect(result.othersMembers).toEqual([]);
    expect(result.bars.map(b => b.label)).toEqual(input.map(b => b.label));
  });

  it('exatamente 11 etapas: 10 nomeadas + Outros representando a unica etapa excedente', () => {
    const input = makeBars(11);
    const result = truncateBars(input);
    expect(result.bars.length).toBe(11);
    expect(result.othersLabel).toBe(OTHERS_LABEL);
    expect(result.othersMembers).toEqual([input[10]!.label]);
    expect(result.bars[10]?.value).toBe(input[10]!.value);
  });

  it('0 etapas: bars vazio, sem erro', () => {
    const result = truncateBars([]);
    expect(result.bars).toEqual([]);
    expect(result.othersLabel).toBeNull();
    expect(result.othersMembers).toEqual([]);
  });

  it('SC-002: invariante bars.length <= limit + 1 para entrada aleatoria', () => {
    for (const n of [0, 1, 5, 9, 10, 11, 12, 20, 47, 100]) {
      const result = truncateBars(makeBars(n));
      expect(result.bars.length).toBeLessThanOrEqual(TRUNCATE_BARS_LIMIT + 1);
    }
  });

  it('respeita limit customizado (ex.: limit=3)', () => {
    const input = makeBars(5);
    const result = truncateBars(input, 3);
    expect(result.bars.length).toBe(4);
    expect(result.othersLabel).toBe(OTHERS_LABEL);
    expect(result.othersMembers).toEqual([input[3]!.label, input[4]!.label]);
  });

  it('nao muta o array de entrada', () => {
    const input = makeBars(14);
    const snapshot = input.map(b => ({ ...b }));
    truncateBars(input);
    expect(input).toEqual(snapshot);
  });
});
