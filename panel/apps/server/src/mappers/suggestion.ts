/**
 * Mapper: SuggestionRow → SuggestionDTO (schema v5 — recall-suggestions).
 *
 * - `referencias` (CSV no DB) → array (vazio quando ausente/em branco).
 * - `severidade` coagida ao enum conhecido (informativa|aviso|impeditiva); valor
 *   desconhecido vira null (defesa em profundidade, como normalizeMemoryType).
 * - `skill_afetada` '' → null para a UI tratar como ausente.
 */
import type { SuggestionDTO, SuggestionSeveridade } from '@cstk-panel/shared-types';
import type { SuggestionRow } from '../db/queries/suggestions.js';

const KNOWN_SEVERIDADES: readonly string[] = ['informativa', 'aviso', 'impeditiva'];

function toSeveridade(raw: string | null): SuggestionSeveridade | null {
  return raw != null && KNOWN_SEVERIDADES.includes(raw)
    ? (raw as SuggestionSeveridade)
    : null;
}

function splitReferencias(raw: string | null): string[] {
  if (!raw) return [];
  return raw
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s !== '');
}

function emptyToNull(s: string | null): string | null {
  return s != null && s.trim() !== '' ? s : null;
}

export function mapSuggestion(row: SuggestionRow): SuggestionDTO {
  return {
    executionId: row.execution_id,
    sourceId: row.source_id,
    affectedSkill: emptyToNull(row.affected_skill),
    severity: toSeveridade(row.severity),
    diagnosis: row.diagnosis,
    proposal: row.proposal,
    referencias: splitReferencias(row.referencias),
    issueOpened: emptyToNull(row.issue_opened),
    createdAt: emptyToNull(row.created_at),
  };
}

export function mapSuggestions(rows: SuggestionRow[]): SuggestionDTO[] {
  return rows.map(mapSuggestion);
}
