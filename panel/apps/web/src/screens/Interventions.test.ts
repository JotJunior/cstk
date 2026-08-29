/**
 * Testes de Interventions (task 4.3.7; FR-001/FR-013/FR-014/FR-015). Sem
 * jsdom/@testing-library neste repo — logica de degradacao/rotulo/validacao
 * extraida como funcoes puras (`interventionsDegradedCopy`, `kindLabel`,
 * `kindColor`, `utf8ByteLength`, `isAnswerReady`) e testada em isolamento,
 * mesmo padrao de `Sessions.test.ts`.
 *
 * Os 4 estados obrigatorios da tela (carregando/vazio/erro/degradado, task
 * 4.3.1) sao compostos em `Interventions()` a partir de `useApiState()` +
 * `LoadingState`/`EmptyState`/`ErrorState`/`DegradedBanner`, todos ja
 * cobertos por seus proprios testes (`useApiState` nao tem teste dedicado,
 * mas e reusado identico a `Sessions.tsx`); aqui cobrimos a parte NOVA e
 * especifica desta tela: a copy de degradacao por `reason` e as regras de
 * apresentacao/validacao por `kind` (procedencia + defaultValue, distincao
 * visual, validacao client-side nao-autoritativa do formulario).
 */
import { describe, it, expect } from 'vitest';
import {
  interventionsDegradedCopy,
  kindLabel,
  kindColor,
  utf8ByteLength,
  isAnswerReady,
} from './Interventions.js';

describe('interventionsDegradedCopy — titulo/subtitulo por reason (4o estado obrigatorio, task 4.3.1)', () => {
  it('cobre bridge_unavailable (unico DegradedReason real desta superficie)', () => {
    const copy = interventionsDegradedCopy('bridge_unavailable');
    expect(copy.title).toMatch(/ponte de intervenções indisponível/i);
  });

  it('nunca lanca excecao e sempre devolve title/subtitle nao-vazios para reason desconhecido ou null', () => {
    for (const reason of [null, 'algum-reason-futuro-nao-mapeado', '']) {
      const copy = interventionsDegradedCopy(reason as never);
      expect(typeof copy.title).toBe('string');
      expect(copy.title.length).toBeGreaterThan(0);
      expect(typeof copy.subtitle).toBe('string');
      expect(copy.subtitle.length).toBeGreaterThan(0);
    }
  });
});

// Task 5.2.2 (Cenario 3 do quickstart, US1 cenario 2): fila vazia (sem
// filas pendentes, SEM degradacao) precisa do estado "vazio explicito" —
// nao tela em branco. Sem jsdom/@testing-library neste repo (ver
// cabecalho), a verificacao e por VARREDURA ESTATICA do source-file: o
// branch `interventions.length === 0` MUST renderizar `<EmptyState .../>`
// com titulo/subtitulo NAO-vazios (nunca `null`/fragmento vazio/apenas a
// lista vazia sem nenhum feedback visual).
describe('5.2.2 — fila vazia usa EmptyState explicito (nao tela em branco, task 4.3.1)', () => {
  it('o branch interventions.length === 0 renderiza EmptyState com title/subtitle nao-vazios', async () => {
    const { readFileSync } = await import('node:fs');
    const { dirname, join } = await import('node:path');
    const { fileURLToPath } = await import('node:url');
    const here = dirname(fileURLToPath(import.meta.url));
    const src = readFileSync(join(here, 'Interventions.tsx'), 'utf8');

    const idx = src.indexOf('interventions.length === 0');
    expect(idx, 'branch de fila vazia (interventions.length === 0) nao encontrado').toBeGreaterThan(-1);

    // Trecho logo apos o branch — deve conter o EmptyState com title/subtitle
    // literais nao-vazios (nunca `undefined`/omitido).
    const snippet = src.slice(idx, idx + 300);
    expect(snippet).toMatch(/<EmptyState\b/);
    expect(snippet).toMatch(/title=["'].+["']/);
    expect(snippet).toMatch(/subtitle=["'].+["']/);
  });
});

describe('kindLabel — rotulo legivel por tipo de intervencao (FR-015, task 4.3.4)', () => {
  it('traduz os 3 tipos fechados', () => {
    expect(kindLabel('choice')).toBe('Escolha');
    expect(kindLabel('confirm')).toBe('Confirmação');
    expect(kindLabel('text')).toBe('Texto livre');
  });

  it('literal desconhecido nunca lanca — devolve o proprio literal', () => {
    expect(kindLabel('futuro-tipo')).toBe('futuro-tipo');
  });
});

describe('kindColor — distincao visual entre os 3 tipos (task 4.3.4)', () => {
  it('os 3 tipos tem cores DISTINTAS entre si', () => {
    const colors = new Set([kindColor('choice'), kindColor('confirm'), kindColor('text')]);
    expect(colors.size).toBe(3);
  });

  it('literal desconhecido cai num fallback neutro, nunca lanca', () => {
    expect(kindColor('futuro-tipo')).toBe('var(--text-3)');
  });
});

describe('utf8ByteLength — contagem em BYTES, nao em caracteres (task 4.3.6, contador de 2048 bytes)', () => {
  it('ascii puro: bytes == caracteres', () => {
    expect(utf8ByteLength('abc')).toBe(3);
  });

  it('acentos/emoji multi-byte contam MAIS bytes que caracteres (nao seria pego por .length)', () => {
    expect(utf8ByteLength('ção')).toBeGreaterThan('ção'.length);
    expect(utf8ByteLength('🎉')).toBe(4); // 1 code point, 4 bytes UTF-8, 2 UTF-16 code units
  });

  it('string vazia tem 0 bytes', () => {
    expect(utf8ByteLength('')).toBe(0);
  });
});

describe('isAnswerReady — validacao de UX NAO-autoritativa por kind (task 4.3.6; FR-005 e regra de SERVIDOR)', () => {
  it('choice: pronto so com um value nao-vazio selecionado', () => {
    expect(isAnswerReady('choice', '', '')).toBe(false);
    expect(isAnswerReady('choice', 'op1', '')).toBe(true);
  });

  it('confirm: pronto so com value em {yes, no}', () => {
    expect(isAnswerReady('confirm', '', '')).toBe(false);
    expect(isAnswerReady('confirm', 'maybe', '')).toBe(false);
    expect(isAnswerReady('confirm', 'yes', '')).toBe(true);
    expect(isAnswerReady('confirm', 'no', '')).toBe(true);
  });

  it('text: pronto com value nao-vazio e texto dentro do teto de 2048 bytes', () => {
    expect(isAnswerReady('text', '', '')).toBe(false);
    expect(isAnswerReady('text', 'answered', 'oi')).toBe(true);
  });

  it('text: NAO pronto quando o texto excede 2048 bytes (mesmo teto do servidor, UX antecipa o 400)', () => {
    const tooLong = 'a'.repeat(2049);
    expect(isAnswerReady('text', 'answered', tooLong)).toBe(false);
  });

  it('kind desconhecido nunca fica pronto (fail-closed) e nunca lanca', () => {
    expect(isAnswerReady('futuro-tipo', 'x', 'y')).toBe(false);
  });
});
