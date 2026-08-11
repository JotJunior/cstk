/**
 * Mapper: WaveRow → WaveDTO.
 * IMPORTANTE: etapas permanece string — NAO converter para array (schema v2).
 * Ref: data-model.md §Entity: Wave; plan.md §Convencoes de Borda
 * Task 3.4.2
 */
import type { WaveDTO } from '@cstk-panel/shared-types';
import type { WaveRow } from '../db/queries/waves.js';

export function mapWave(row: WaveRow): WaveDTO {
  return {
    wave: row.wave,
    executionId: row.execution_id,
    stages: row.stages,           // string unica — NAO array
    startedAt: row.started_at,
    finishedAt: row.finished_at,
    wallclockSeconds: row.wallclock_seconds,
    toolCalls: row.tool_calls,
    terminationReason: row.termination_reason,
    nStages: row.n_stages,
    nSkills: row.n_skills,
    session: row.session,
    // schema v10 — passa NULL adiante sem coalescer para 0 (Principio III):
    // "nao medido" e "medido e deu zero" nao podem virar o mesmo numero.
    agentSpawnsTotal: row.agent_spawns_total,
    agentSpawnsWithUsage: row.agent_spawns_with_usage,
    agentTotalTokens: row.agent_total_tokens,
    agentInputTokens: row.agent_input_tokens,
    agentOutputTokens: row.agent_output_tokens,
    agentCacheReadTokens: row.agent_cache_read_tokens,
    agentCacheCreationTokens: row.agent_cache_creation_tokens,
    agentToolUseCount: row.agent_tool_use_count,
    agentDurationMs: row.agent_duration_ms,
    // schema v11 — telemetria OTel. Mesma regra: NULL sobe como null. O custo
    // e fracionario e NAO e arredondado aqui; formatacao e da borda de UI.
    otelCostUsd: row.otel_cost_usd,
    otelCostMainUsd: row.otel_cost_main_usd,
    otelCostSubagentUsd: row.otel_cost_subagent_usd,
    otelTotalTokens: row.otel_total_tokens,
    otelSubagentTokens: row.otel_subagent_tokens,
    // schema v12 — breakdown de tokens por fonte (main/subagente) x tipo
    // (input/output/cache read/cache creation). Um lado pode vir null com o
    // outro preenchido: sao coletas independentes, nao um par.
    otelMainInputTokens: row.otel_main_input_tokens,
    otelMainOutputTokens: row.otel_main_output_tokens,
    otelMainCacheReadTokens: row.otel_main_cache_read_tokens,
    otelMainCacheCreationTokens: row.otel_main_cache_creation_tokens,
    otelSubagentInputTokens: row.otel_subagent_input_tokens,
    otelSubagentOutputTokens: row.otel_subagent_output_tokens,
    otelSubagentCacheReadTokens: row.otel_subagent_cache_read_tokens,
    otelSubagentCacheCreationTokens: row.otel_subagent_cache_creation_tokens,
  };
}

export function mapWaves(rows: WaveRow[]): WaveDTO[] {
  return rows.map(mapWave);
}
