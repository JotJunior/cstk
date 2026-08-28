/**
 * Mapper: EventRow → EventDTO.
 * Task 3.4.5
 */
import type { EventDTO } from '@cstk-panel/shared-types';
import type { EventRow } from '../db/queries/events.js';

type ValidEventType =
  | 'lock_contention' | 'validation_failed' | 'wave_retry' | 'schedule_wait'
  | 'recall_consulted';  // schema v3 — consulta do read-back loop (FR-V3-006)
const VALID_EVENT_TYPES = new Set<string>([
  'lock_contention', 'validation_failed', 'wave_retry', 'schedule_wait',
  'recall_consulted',
]);

function toEventType(raw: string): ValidEventType {
  if (VALID_EVENT_TYPES.has(raw)) return raw as ValidEventType;
  // Fallback para tipo nao reconhecido — preservar como schedule_wait (mais seguro)
  return 'schedule_wait';
}

export function mapEvent(row: EventRow): EventDTO {
  return {
    executionId: row.execution_id,
    eventType: toEventType(row.event_type),
    timestamp: row.timestamp,
    description: row.description,
  };
}

export function mapEvents(rows: EventRow[]): EventDTO[] {
  return rows.map(mapEvent);
}
