/**
 * Queries read-only para entidade decisions.
 * Ref: data-model.md §Entity: Decision; spec.md FR-003; contracts/api-read.md
 * Task 3.3.3
 *
 * Campos textuais (context, rationale, evidence) sao UNTRUSTED —
 * chegam crus do DB, mapeados para DTO sem transformacao.
 * O FE renderiza via textContent, nunca innerHTML.
 *
 * FASE 2 (new-schema): Row interface migrada pt-BR→EN snake_case (task 2.3).
 */
import type Database from 'better-sqlite3';
import { hasColumn } from '../columns.js';

export interface DecisionRow {
  wave: string;
  execution_id: string;
  stage: string | null;
  agent: string | null;
  choice: string | null;
  options: string | null;     // schema v6; NULL em bases v<6 (FR-V3-005)
  score: number | null;
  context: string | null;     // @untrusted
  rationale: string | null;   // @untrusted
  evidence: string | null;    // @untrusted
  decision_class: string | null;          // schema v15; enum fechado estrutural|operacional; NULL em bases v<15/legado
  structural_axis: string | null;         // schema v15; enum fechado de eixos; NULL quando nao estrutural
  human_consent_block_id: string | null;  // schema v15; id block-NNN do BloqueioHumano que consente
}

/**
 * Projecao de `options` tolerante a bases v<6 (recall schema v6 adicionou a
 * coluna `decisions.options`): coluna ausente → `NULL AS options`, mantendo uma
 * unica forma de Row (Principio II — degradar em vez de quebrar).
 */
function optionsSelect(db: Database.Database): string {
  return hasColumn(db, 'decisions', 'options') ? 'options' : 'NULL as options';
}

/**
 * Projecao de `evidence` tolerante a bases mais antigas.
 */
function evidenceSelect(db: Database.Database): string {
  return hasColumn(db, 'decisions', 'evidence') ? 'evidence' : 'NULL as evidence';
}

/**
 * Projecao das colunas do gate estrutural (schema v15) tolerante a bases v<15:
 * coluna ausente → `NULL AS <col>`, mantendo uma unica forma de Row
 * (Principio II — degradar em vez de quebrar; mesmo padrao de `options`).
 */
function structuralGateSelect(db: Database.Database): string {
  return ['decision_class', 'structural_axis', 'human_consent_block_id']
    .map((col) => (hasColumn(db, 'decisions', col) ? col : `NULL as ${col}`))
    .join(', ');
}

export interface DecisionFilters {
  wave?: string;
  stage?: string;
  score?: number;
  limit: number;
  offset: number;
}

/** Lista decisoes paginadas de uma execucao com filtros opcionais */
export function listDecisions(
  db: Database.Database,
  executionId: string,
  filters: DecisionFilters
): DecisionRow[] {
  // Construir WHERE dinamico com bindings posicionais (nunca interpolacao)
  const conditions: string[] = ['execution_id = ?'];
  const params: unknown[] = [executionId];

  if (filters.wave !== undefined) {
    conditions.push('wave = ?');
    params.push(filters.wave);
  }
  if (filters.stage !== undefined) {
    conditions.push('stage = ?');
    params.push(filters.stage);
  }
  if (filters.score !== undefined) {
    conditions.push('score = ?');
    params.push(filters.score);
  }

  // limit e offset sempre como bindings (SC-008)
  params.push(filters.limit, filters.offset);

  const where = conditions.join(' AND ');
  return db
    .prepare(`
      SELECT wave, execution_id, stage, agent, choice, ${optionsSelect(db)}, score,
             context, rationale, ${evidenceSelect(db)}, ${structuralGateSelect(db)}
      FROM decisions
      WHERE ${where}
      ORDER BY rowid ASC
      LIMIT ? OFFSET ?
    `)
    .all(...params) as DecisionRow[];
}

/** Conta total de decisoes de uma execucao (para paginacao) */
export function countDecisions(
  db: Database.Database,
  executionId: string,
  filters: Omit<DecisionFilters, 'limit' | 'offset'>
): number {
  const conditions: string[] = ['execution_id = ?'];
  const params: unknown[] = [executionId];

  if (filters.wave !== undefined) {
    conditions.push('wave = ?');
    params.push(filters.wave);
  }
  if (filters.stage !== undefined) {
    conditions.push('stage = ?');
    params.push(filters.stage);
  }
  if (filters.score !== undefined) {
    conditions.push('score = ?');
    params.push(filters.score);
  }

  const where = conditions.join(' AND ');
  const row = db
    .prepare(`SELECT count(*) as n FROM decisions WHERE ${where}`)
    .get(...params) as { n: number };
  return row.n;
}

/** Distribuicao de score (0..3) das decisoes de UMA execucao (card lateral). */
export interface ScoreDistRow { score: number; count: number; }

export function getDecisionScoreDistribution(
  db: Database.Database,
  executionId: string
): ScoreDistRow[] {
  return db
    .prepare(`
      SELECT score, count(*) as count
      FROM decisions
      WHERE execution_id = ? AND score IS NOT NULL
      GROUP BY score
      ORDER BY score ASC
    `)
    .all(executionId) as ScoreDistRow[];
}
