/**
 * Mapper: BlockRow → BlockDTO.
 * Task 3.4.5 / FASE 2+3 (new-schema): rename BloqueioRow→BlockRow, BloqueioDTO→BlockDTO.
 */
import type { BlockDTO } from '@cstk-panel/shared-types';
import type { BlockRow } from '../db/queries/blocks.js';

export function mapBlock(row: BlockRow): BlockDTO {
  return {
    executionId: row.execution_id,
    status: row.status,
    question: row.question,
    contextForAnswer: row.context_for_answer,
    answer: row.answer,
    decisionId: row.decision_id,
    triggeredAt: row.triggered_at,
    answeredAt: row.answered_at,
    latencySeconds: row.latency_seconds,
  };
}

export function mapBlocks(rows: BlockRow[]): BlockDTO[] {
  return rows.map(mapBlock);
}

// Back-compat aliases (remove after FASE 3 cleanup)
export const mapBloqueio = mapBlock;
export const mapBloqueios = mapBlocks;
