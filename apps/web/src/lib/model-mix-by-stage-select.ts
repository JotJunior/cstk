/**
 * model-mix-by-stage-select — funcao pura que agrupa e ordena o payload de
 * `GET /metrics/model-mix-by-stage` (mix de modelos por etapa, DERIVADO de
 * `decisions.choice LIKE 'model:%'`, `meta.approximate=true`) para o card
 * empilhado "Mix de modelos por etapa" em Metricas.
 *
 * Corrige o defeito da FASE 6 (spec.md US4, FR-009; contracts/
 * existing-endpoints.md): o payload real projeta o campo `stage` (ingles) —
 * `etapa` NUNCA existiu no contrato real (`ModelMixByStageRow`,
 * apps/server/src/db/queries/metrics.ts:352 `SELECT stage, modelo, n ...`).
 * Ler `r.stage` aqui e o UNICO ponto de leitura do campo de etapa deste
 * card — antes disso, `Metrics.tsx` lia `r.etapa` (inexistente), colapsando
 * todas as linhas no rotulo `'?'`.
 *
 * Ordena por `SDD_STAGES` (ordem canonica do pipeline SDD), nao por volume
 * (FR-009); etapas fora da constante (dado legado/desconhecido, ex:
 * `model-routing` na fixture de teste) vao ao final, ordenadas por volume
 * total desc, com o rotulo real preservado (nunca descartadas).
 *
 * Funcao PURA (sem React/DOM), seguindo o precedente de `overview-select.ts`
 * / `model-usage-select.ts`.
 */
import { SDD_STAGES } from './constants.js';

/** Uma barra empilhada: rotulo do eixo X (`d`) + contagem por modelo. */
export interface StageBarDatum {
  d: string;
  [model: string]: number | string;
}

const STAGE_ORDER = new Map<string, number>(SDD_STAGES.map((s, i) => [s, i]));

/**
 * Agrupa linhas cruas `{ stage, modelo, n }` (payload de
 * `/metrics/model-mix-by-stage`) por etapa — somando `n` por modelo dentro
 * de cada etapa — e ordena o resultado: etapas conhecidas em `SDD_STAGES`
 * primeiro (ordem canonica do pipeline), etapas desconhecidas ao final
 * ordenadas por volume total desc.
 *
 * Le exclusivamente `r.stage`/`r.modelo`/`r.n` — nunca `r.etapa` (campo que
 * nunca existiu no payload real).
 */
export function buildStageBars(rows: Record<string, unknown>[]): StageBarDatum[] {
  const byStage = new Map<string, StageBarDatum>();
  const totalByStage = new Map<string, number>();
  for (const r of rows) {
    const stage = (r.stage as string | null) ?? '?';
    const modelo = (r.modelo as string | null) ?? '?';
    const n = (r.n as number | null) ?? 0;
    const row = byStage.get(stage) ?? { d: stage.slice(0, 8) };
    row[modelo] = ((row[modelo] as number | undefined) ?? 0) + n;
    byStage.set(stage, row);
    totalByStage.set(stage, (totalByStage.get(stage) ?? 0) + n);
  }
  const stages = [...byStage.keys()];
  const known = stages
    .filter(s => STAGE_ORDER.has(s))
    .sort((a, b) => (STAGE_ORDER.get(a) as number) - (STAGE_ORDER.get(b) as number));
  const unknown = stages
    .filter(s => !STAGE_ORDER.has(s))
    .sort((a, b) => (totalByStage.get(b) ?? 0) - (totalByStage.get(a) ?? 0));
  return [...known, ...unknown].map(s => byStage.get(s) as StageBarDatum);
}
