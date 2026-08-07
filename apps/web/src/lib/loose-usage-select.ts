/**
 * loose-usage-select — normaliza a resposta do endpoint `/metrics/loose-usage`
 * (schema v13, `loose_usage`, cstk 6.6.0) no view-model do card de consumo
 * avulso. Funcao PURA (sem React/DOM), mesmo precedente de
 * `model-usage-select.ts`: trava o contrato de borda e concentra a regra
 * `null` != `0` (Principio III — Honestidade de Metrica) num unico lugar
 * testavel.
 *
 * Consumo AVULSO = sessoes interativas comuns do Claude Code, fora de
 * qualquer execucao agente-00c/feature-00c. A captura e OPT-IN
 * (`cstk hooks install --with-loose-usage`): tabela presente e vazia significa
 * "sem medicao", nunca "sem consumo" — os estados nao podem colapsar.
 */
import type { LooseUsageResult, LooseUsageCoverage, LooseUsageComparison, LooseUsageProjectEntry, LooseUsageModelEntry } from '@cstk-panel/shared-types';

export type LooseUsageState =
  /** tabela `loose_usage` ausente na base (schema v2-v12) — meta.reason='table-empty' */
  | 'degraded'
  /** tabela presente, zero linhas no recorte (captura opt-in desligada ou sem sessao avulsa) */
  | 'empty'
  /** ha consumo avulso medido no recorte */
  | 'measured';

export interface LooseUsageVM {
  state: LooseUsageState;
  /** por projeto, ordenado por `costUsd` desc com `null` por ultimo */
  byProject: LooseUsageProjectEntry[];
  /** por modelo (rotulo BRUTO do OTel), mesma ordenacao */
  byModel: LooseUsageModelEntry[];
  comparison: LooseUsageComparison;
  coverage: LooseUsageCoverage;
}

const EMPTY_COVERAGE: LooseUsageCoverage = {
  rowsTotal: null,
  segmentsTotal: null,
  segmentsOpen: null,
  processes: null,
  projects: null,
  lastCapturedAt: null,
};

const EMPTY_COMPARISON: LooseUsageComparison = {
  loose: { costUsd: null, totalTokens: null, blendedCostPerMtok: null },
  pipeline: { costUsd: null, totalTokens: null, blendedCostPerMtok: null },
};

/**
 * Deriva o estado inteiramente da FORMA do `data` (mesmo padrao de
 * `deriveState` do model-usage-select): `coverage.rowsTotal == null` so
 * acontece no caminho degradado `table-empty`; tabela presente e vazia
 * preserva `rowsTotal` como numero (`0`).
 */
function deriveState(byProject: LooseUsageProjectEntry[], coverage: LooseUsageCoverage): LooseUsageState {
  if (coverage.rowsTotal == null) return 'degraded';
  if (byProject.length === 0) return 'empty';
  return 'measured';
}

export function selectLooseUsage(raw: LooseUsageResult | null | undefined): LooseUsageVM {
  const byProject = raw?.byProject ?? [];
  const byModel = raw?.byModel ?? [];
  const comparison = raw?.comparison ?? EMPTY_COMPARISON;
  const coverage = raw?.coverage ?? EMPTY_COVERAGE;
  return {
    state: deriveState(byProject, coverage),
    byProject,
    byModel,
    comparison,
    coverage,
  };
}

/**
 * Rotulo fixo de natureza do dado: custo/tokens vem de `sum()` direto sobre a
 * telemetria OTel capturada pelo hook — MEDIDO, nunca estimado pelo painel.
 */
export const LOOSE_USAGE_NATURE_LABEL = 'medido' as const;

/** Texto curto de cobertura da amostra avulsa — mesmo padrao dos irmaos. */
export function looseUsageCoverageLabel(coverage: LooseUsageCoverage): string {
  if (coverage.rowsTotal == null) return 'dado não coletado nesta base';
  const seg = coverage.segmentsTotal ?? 0;
  const proc = coverage.processes ?? 0;
  const open = coverage.segmentsOpen ?? 0;
  const base = `${seg} segmento${seg === 1 ? '' : 's'} · ${proc} processo${proc === 1 ? '' : 's'}`;
  return open > 0 ? `${base} · ${open} em captura` : base;
}

/**
 * Formata o custo blended por Mtok — `null` renderiza "não medido", nunca
 * "$0" (FR-005/SC-004 do cstk: divisao indefinida nao vira zero).
 */
export function fmtBlendedPerMtok(v: number | null | undefined): string {
  if (v == null) return 'não medido';
  return `$${v.toFixed(2)}/Mtok`;
}
