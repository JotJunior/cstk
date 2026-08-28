/**
 * Mapper: AlertRow → AlertSignalDTO.
 * Task 3.4.5
 */
import type { AlertSignalDTO } from '@cstk-panel/shared-types';
import type { AlertRow } from '../db/queries/alerts.js';

type ValidType = 'circular' | 'budget_breach';
const VALID_TYPES = new Set<string>(['circular', 'budget_breach']);

function toTipo(raw: string): ValidType {
  if (VALID_TYPES.has(raw)) return raw as ValidType;
  return 'budget_breach';
}

export function mapAlert(row: AlertRow): AlertSignalDTO {
  return {
    executionId: row.execution_id,
    type: toTipo(row.type),
    subtype: row.subtype,
    consumedValue: row.consumed_value,
    thresholdValue: row.threshold_value,
    description: row.description,
    wave: row.wave,
  };
}

export function mapAlerts(rows: AlertRow[]): AlertSignalDTO[] {
  return rows.map(mapAlert);
}
