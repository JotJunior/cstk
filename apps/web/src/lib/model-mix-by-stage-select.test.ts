import { describe, it, expect } from 'vitest';
import { buildStageBars } from './model-mix-by-stage-select.js';

// Payload representativo no SHAPE REAL do endpoint /metrics/model-mix-by-stage
// (apps/server/src/db/queries/metrics.ts:352 `ModelMixByStageRow`):
// `stage` (ingles, chave real) + `modelo` (pt-BR, legado deliberado — nao
// renomear, quebraria contrato v7) + `n`.
const realPayload: Record<string, unknown>[] = [
  { stage: 'execute-task', modelo: 'sonnet', n: 20 },
  { stage: 'clarify', modelo: 'haiku', n: 5 },
  { stage: 'specify', modelo: 'opus', n: 2 },
  { stage: 'clarify', modelo: 'sonnet', n: 3 },
];

describe('buildStageBars', () => {
  it('le r.stage — nunca r.etapa (defeito FASE 6): linha sem stage cai no rotulo "?" isolado', () => {
    const rows = [{ etapa: 'plan', modelo: 'sonnet', n: 7 }];
    const bars = buildStageBars(rows);
    // Sem `stage`, a linha nao e atribuida a 'plan' (que seria o bug antigo
    // se o codigo lesse `.etapa`) — cai isolada no grupo '?'.
    expect(bars).toHaveLength(1);
    expect(bars[0]?.d).toBe('?');
    expect(bars[0]?.sonnet).toBe(7);
  });

  it('agrupa e soma n por (stage, modelo)', () => {
    const bars = buildStageBars(realPayload);
    const clarify = bars.find(b => b.d === 'clarify');
    expect(clarify).toBeDefined();
    expect(clarify?.haiku).toBe(5);
    expect(clarify?.sonnet).toBe(3);
  });

  it('ordena etapas conhecidas pela ordem canonica de SDD_STAGES, nao por volume', () => {
    // 'execute-task' tem o maior volume (20) mas vem DEPOIS de 'specify' e
    // 'clarify' na ordem do pipeline — a ordenacao por volume colocaria
    // execute-task primeiro; a ordenacao correta (FR-009) nao.
    const bars = buildStageBars(realPayload);
    const order = bars.map(b => b.d);
    // rotulo truncado a 8 chars (mesma convencao do eixo X do chart) —
    // 'execute-task'.slice(0, 8) === 'execute-'.
    expect(order).toEqual(['specify', 'clarify', 'execute-']);
  });

  it('etapas fora de SDD_STAGES vao ao final, ordenadas por volume desc, sem serem descartadas', () => {
    const rows: Record<string, unknown>[] = [
      { stage: 'clarify', modelo: 'sonnet', n: 1 },
      { stage: 'legacy-unknown-stage', modelo: 'opus', n: 50 },
      { stage: 'another-unknown', modelo: 'haiku', n: 5 },
    ];
    const bars = buildStageBars(rows);
    const order = bars.map(b => b.d);
    // conhecida primeiro; desconhecidas ao final ordenadas por volume desc
    // (label truncado a 8 chars, mesma convencao do eixo X do chart).
    expect(order).toEqual(['clarify', 'legacy-u', 'another-']);
  });

  it('lista vazia produz array vazio (sem inventar etapa)', () => {
    expect(buildStageBars([])).toEqual([]);
  });
});
