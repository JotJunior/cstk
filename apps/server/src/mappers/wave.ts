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
  };
}

export function mapWaves(rows: WaveRow[]): WaveDTO[] {
  return rows.map(mapWave);
}
