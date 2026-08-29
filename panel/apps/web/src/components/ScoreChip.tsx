/**
 * ScoreChip — score 0..3 com cor semantica.
 * 0 = vermelho (pausa/humano), 1 = amarelo, 2 = amarelo-claro, 3 = verde.
 * Ref: spec.md FR-021; data-model.md §DecisionDTO
 */
import type { DecisionDTO } from '@cstk-panel/shared-types';

type Score = DecisionDTO['score'];

const SCORE_TITLES: Record<number, string> = {
  0: 'score 0 — pausa/humano',
  1: 'score 1 — decide se outras opcoes violam constitution',
  2: 'score 2 — decide por contexto (briefing/constitution/stack)',
  3: 'score 3 — decide com evidencia empirica',
};

interface ScoreChipProps {
  score: Score;
}

export function ScoreChip({ score }: ScoreChipProps) {
  if (score == null) {
    return <span className="score" style={{ color: 'var(--text-3)', background: 'var(--bg-3)' }}>?</span>;
  }
  return (
    <span className={`score s${score}`} title={SCORE_TITLES[score] ?? `score ${score}`}>
      {score}
    </span>
  );
}
