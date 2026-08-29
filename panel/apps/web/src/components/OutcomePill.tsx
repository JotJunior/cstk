/**
 * OutcomePill — resultado pass/fail de Task com cor semantica.
 * Ref: data-model.md §TaskDTO; spec.md FR-021
 */
import type { TaskDTO } from '@cstk-panel/shared-types';

type Outcome = TaskDTO['outcome'];

interface OutcomePillProps {
  outcome: Outcome;
}

export function OutcomePill({ outcome }: OutcomePillProps) {
  if (!outcome) {
    return <span className="pill" style={{ color: 'var(--text-3)', background: 'var(--bg-3)' }}>-</span>;
  }
  return (
    <span className={`pill ${outcome}`}>
      {outcome === 'pass' ? '✓ pass' : '✕ fail'}
    </span>
  );
}
