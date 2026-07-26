/**
 * Mapper: colunas `agent_*` (schema v10) → AgentUsageRollup.
 * Fonte: waves.agent_* agregado por `cstk recall --ingest` a partir de
 * `.waves[].agent_usage` do state.json (feature cstk wave-token-metrics).
 *
 * Principio III (Honestidade de Metrica): NENHUM campo e coalescido para 0.
 * `null` significa "sem numero" e sobe assim ate a UI, que exibe "—" e o
 * denominador de cobertura em vez de um total que pareceria completo.
 */
import type { AgentUsageRollup } from '@cstk-panel/shared-types';
import type { AgentUsageRollupRow } from '../db/queries/executions.js';
import type { AgentUsageResult } from '../db/queries/metrics.js';

export function mapAgentUsageRollup(row: AgentUsageRollupRow): AgentUsageRollup {
  return {
    spawnsTotal: row.agent_spawns_total,
    spawnsWithUsage: row.agent_spawns_with_usage,
    totalTokens: row.agent_total_tokens,
    inputTokens: row.agent_input_tokens,
    outputTokens: row.agent_output_tokens,
    cacheReadTokens: row.agent_cache_read_tokens,
    cacheCreationTokens: row.agent_cache_creation_tokens,
    toolUseCount: row.agent_tool_use_count,
    durationMs: row.agent_duration_ms,
    wavesWithUsage: row.agent_waves_with_usage,
    wavesTotal: row.agent_waves_total,
  };
}

/** O resultado agregado de /metrics/agent-usage ja nasce em camelCase. */
export function mapAgentUsageResult(result: AgentUsageResult): AgentUsageRollup {
  return { ...result };
}
