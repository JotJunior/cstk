/**
 * Mapper: DecisionRow → DecisionDTO.
 * score: INTEGER → 0|1|2|3|null.
 * Campos UNTRUSTED preservados crus — FE renderiza via textContent.
 * Ref: data-model.md §Entity: Decision; plan.md §Convencoes de Borda
 * Task 3.4.3
 */
import type { DecisionDTO } from '@cstk-panel/shared-types';
import type { DecisionRow } from '../db/queries/decisions.js';

type ValidScore = 0 | 1 | 2 | 3;

function toScore(raw: number | null): ValidScore | null {
  if (raw === 0 || raw === 1 || raw === 2 || raw === 3) return raw;
  return null;
}

export function mapDecision(row: DecisionRow): DecisionDTO {
  return {
    wave: row.wave,
    executionId: row.execution_id,
    stage: row.stage,
    agent: row.agent,
    choice: row.choice,
    // JSON array cru (estruturado, sem scrub na ingestao) — FE deriva chips
    options: row.options,
    score: toScore(row.score),
    // Campos UNTRUSTED — preservar crus, sem sanitizacao aqui
    // FE renderiza via textContent/pre, NUNCA innerHTML
    context: row.context,
    rationale: row.rationale,
    evidencia: row.evidence,
    // Gate estrutural (schema v15) — enums fechados + id block-NNN; NULL em legado
    decisionClass: row.decision_class,
    structuralAxis: row.structural_axis,
    humanConsentBlockId: row.human_consent_block_id,
  };
}

export function mapDecisions(rows: DecisionRow[]): DecisionDTO[] {
  return rows.map(mapDecision);
}
