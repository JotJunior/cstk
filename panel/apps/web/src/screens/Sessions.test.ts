/**
 * Testes de Sessions (task 6.3.4; US1/US3). Sem jsdom/@testing-library
 * neste repo — logica de degradacao/formatacao extraida como funcoes puras
 * (`sessionsDegradedCopy`, `fmtSessionBytes`, `sessionProjectLabel`) e
 * testada em isolamento, mesmo padrao de `Executions.test.ts`.
 */
import { describe, it, expect } from 'vitest';
import { sessionsDegradedCopy, fmtSessionBytes, sessionProjectLabel } from './Sessions.js';

describe('sessionsDegradedCopy — um titulo/subtitulo legivel por reason (US3)', () => {
  it('cobre sessions-root-missing', () => {
    const copy = sessionsDegradedCopy('sessions-root-missing');
    expect(copy.title).toMatch(/raiz de sessões ausente/i);
  });

  it('cobre sessions-root-unreadable', () => {
    const copy = sessionsDegradedCopy('sessions-root-unreadable');
    expect(copy.title).toMatch(/permissão de leitura/i);
  });

  it('nunca lanca excecao e sempre devolve title/subtitle nao-vazios para reason desconhecido ou null', () => {
    for (const reason of [null, 'algum-reason-futuro-nao-mapeado', '']) {
      const copy = sessionsDegradedCopy(reason as never);
      expect(typeof copy.title).toBe('string');
      expect(copy.title.length).toBeGreaterThan(0);
      expect(typeof copy.subtitle).toBe('string');
      expect(copy.subtitle.length).toBeGreaterThan(0);
    }
  });
});

describe('fmtSessionBytes', () => {
  it('formata bytes, KB e MB', () => {
    expect(fmtSessionBytes(500)).toBe('500 B');
    expect(fmtSessionBytes(2048)).toBe('2.0 KB');
    expect(fmtSessionBytes(3 * 1024 * 1024)).toBe('3.0 MB');
  });

  it('null/undefined vira travessao, nunca excecao', () => {
    expect(fmtSessionBytes(null)).toBe('—');
    expect(fmtSessionBytes(undefined)).toBe('—');
  });
});

describe('sessionProjectLabel', () => {
  it('prefere projectPath quando presente', () => {
    expect(sessionProjectLabel({ projectPath: '/a/b', projectSlug: '-a-b' })).toBe('/a/b');
  });

  it('cai para projectSlug quando projectPath e null', () => {
    expect(sessionProjectLabel({ projectPath: null, projectSlug: '-a-b' })).toBe('-a-b');
  });
});
