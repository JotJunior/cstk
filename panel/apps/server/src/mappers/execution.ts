/**
 * Mapper: ExecutionRow → ExecutionDTO.
 * snake_case → camelCase conforme plan.md §Convencoes de Borda.
 * Ref: data-model.md §Entity: Execution; spec.md FR-001
 * Task 3.4.1
 */
import type { ExecutionDTO } from '@cstk-panel/shared-types';
import type { ExecutionRow } from '../db/queries/executions.js';
import { normalizeStatus } from './status.js';

export function mapExecution(row: ExecutionRow): ExecutionDTO {
  return {
    project: row.project,
    feature: row.feature,
    executionId: row.execution_id,
    status: normalizeStatus(row.status),
    terminationReason: row.termination_reason,
    currentStage: row.current_stage,
    startedAt: row.started_at,
    finishedAt: row.finished_at,
    durationSeconds: row.duration_seconds,
    suggestedStack: row.suggested_stack,
    wavesTotal: row.waves_total,
    toolCallsTotal: row.tool_calls_total,
    wallclockTotalSeconds: row.wallclock_total_seconds,
    subagentsSpawned: row.subagents_spawned,
    maxDepth: row.max_depth,
    decisionsTotal: row.decisions_total,
    humanBlocksTotal: row.human_blocks_total,
    skillSuggestionsTotal: row.skill_suggestions_total,
    toolkitIssuesOpened: row.toolkit_issues_opened,
    session: row.session,
  };
}

export function mapExecutions(rows: ExecutionRow[]): ExecutionDTO[] {
  return rows.map(mapExecution);
}
