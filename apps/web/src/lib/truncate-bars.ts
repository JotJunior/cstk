/**
 * truncate-bars — trunca uma lista de barras ja ordenada por volume desc em
 * top-N nomeadas + 1 barra agregada "Outros" para a (N+1)-esima entrada em
 * diante (FR-006/007/008, SC-002 do spec.md `dashboard-refactor`).
 *
 * Funcao PURA (sem React/DOM) — a regra de truncamento nao vive no `.tsx`
 * (research.md, Decision 5; data-model.md Parte C `TruncatedBars`), o que a
 * torna testavel isoladamente (quickstart.md Cenario 5).
 *
 * Contrato: `input` deve chegar ja ordenado por volume desc (os endpoints de
 * metricas ja retornam ordenados, ex.: `getThroughputByStage` — `ORDER BY
 * count DESC`); esta funcao NAO reordena.
 */

export interface TruncatedBar {
  label: string;
  value: number;
}

export interface TruncatedBars {
  /** no maximo `limit + 1` itens (SC-002: com limit=10, `bars.length <= 11`). */
  bars: TruncatedBar[];
  /** `'Outros'` quando houve agregacao; `null` caso contrario (ex.: <= limit entradas). */
  othersLabel: string | null;
  /** rotulos das entradas somadas em "Outros" (FR-007; US3 cenario 3). */
  othersMembers: string[];
}

/** Quantidade de barras nomeadas antes de agregar o restante em "Outros". */
export const TRUNCATE_BARS_LIMIT = 10;

/** Rotulo fixo da barra agregada (FR-006/007). */
export const OTHERS_LABEL = 'Outros';

/**
 * Regras (data-model.md Parte C + quickstart.md Cenario 5):
 * - <= `limit` entradas: todas nomeadas, `othersLabel: null`, sem agregacao.
 * - > `limit` entradas: as `limit` primeiras ficam nomeadas; a partir da
 *   `limit + 1`-esima, os valores sao somados numa unica barra "Outros".
 * - 0 entradas: `{ bars: [], othersLabel: null, othersMembers: [] }`.
 * - Invariante SC-002: `bars.length <= limit + 1` sempre.
 */
export function truncateBars(input: readonly TruncatedBar[], limit = TRUNCATE_BARS_LIMIT): TruncatedBars {
  if (input.length <= limit) {
    return { bars: input.map(b => ({ ...b })), othersLabel: null, othersMembers: [] };
  }
  const named = input.slice(0, limit).map(b => ({ ...b }));
  const rest = input.slice(limit);
  const othersValue = rest.reduce((sum, item) => sum + item.value, 0);
  return {
    bars: [...named, { label: OTHERS_LABEL, value: othersValue }],
    othersLabel: OTHERS_LABEL,
    othersMembers: rest.map(item => item.label),
  };
}
