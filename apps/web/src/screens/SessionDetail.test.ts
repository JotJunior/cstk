/**
 * Testes de SessionDetail (task 6.3.4; US2/US3). Sem jsdom/@testing-library
 * neste repo — logica de degradacao/chave extraida como funcoes puras
 * (`sessionDetailDegradedCopy`, `sessionEntryKey`) e testada em isolamento.
 */
import { describe, it, expect } from 'vitest';
import { sessionDetailDegradedCopy, sessionEntryKey } from './SessionDetail.js';

describe('sessionDetailDegradedCopy — cobre TODOS os reasons de GET /sessions/:id/tail (US3)', () => {
  it('cobre session-not-found', () => {
    expect(sessionDetailDegradedCopy('session-not-found').title).toMatch(/não encontrada/i);
  });

  it('cobre session-rejected', () => {
    expect(sessionDetailDegradedCopy('session-rejected').title).toMatch(/rejeitado/i);
  });

  it('cobre sessions-root-missing', () => {
    expect(sessionDetailDegradedCopy('sessions-root-missing').title).toMatch(/raiz de sessões ausente/i);
  });

  it('cobre session-scrub-failed (nunca exibe texto cru — apenas o aviso)', () => {
    const copy = sessionDetailDegradedCopy('session-scrub-failed');
    expect(copy.title).toMatch(/filtro de segredos/i);
  });

  it('nunca lanca excecao e sempre devolve title/subtitle nao-vazios para reason desconhecido ou null', () => {
    for (const reason of [null, 'reason-futuro-nao-mapeado', '']) {
      const copy = sessionDetailDegradedCopy(reason as never);
      expect(typeof copy.title).toBe('string');
      expect(copy.title.length).toBeGreaterThan(0);
      expect(typeof copy.subtitle).toBe('string');
      expect(copy.subtitle.length).toBeGreaterThan(0);
    }
  });
});

describe('sessionEntryKey', () => {
  it('usa uuid quando presente', () => {
    expect(sessionEntryKey({ uuid: 'abc-123' }, 5)).toBe('abc-123');
  });

  it('cai para o indice quando uuid e null (linhas legadas sem uuid)', () => {
    expect(sessionEntryKey({ uuid: null }, 2)).toBe('entry-2');
  });
});
