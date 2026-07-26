/**
 * Mapper: colunas `otel_*` (schema v11) → OtelUsageRollup.
 * Fonte: waves.otel_* agregado por `cstk recall --ingest` a partir de
 * `.waves[].otel_usage` do state.json (cstk 5.30.0).
 *
 * Principio III (Honestidade de Metrica): nenhum campo e coalescido para 0 —
 * `null` significa "onda sem coleta OTel" (telemetria desligada, execucao
 * anterior a 5.28.0 ou base v<11) e sobe assim ate a UI.
 *
 * O custo em USD NAO e calculado aqui: ele ja vem calculado pelo Claude Code
 * e gravado pelo cstk. O painel apenas soma — nao ha tabela de preco embutida.
 */
import type { OtelUsageRollup } from '@cstk-panel/shared-types';
import type { OtelUsageRollupRow } from '../db/queries/executions.js';
import type { OtelUsageResult } from '../db/queries/metrics.js';

export function mapOtelUsageRollup(row: OtelUsageRollupRow): OtelUsageRollup {
  return {
    costUsd: row.otel_cost_usd,
    costMainUsd: row.otel_cost_main_usd,
    costSubagentUsd: row.otel_cost_subagent_usd,
    totalTokens: row.otel_total_tokens,
    subagentTokens: row.otel_subagent_tokens,
    wavesWithOtel: row.otel_waves_with_usage,
    wavesTotal: row.otel_waves_total,
  };
}

/** O resultado agregado de /metrics/otel-usage ja nasce em camelCase. */
export function mapOtelUsageResult(result: OtelUsageResult): OtelUsageRollup {
  return { ...result };
}
