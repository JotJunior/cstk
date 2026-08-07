/**
 * Consumo AVULSO (schema v13 — cstk 6.6.0, `loose_usage`).
 * Ref: ../cstk/docs/specs/loose-usage-capture/data-model.md;
 * ../cstk/docs/cstk-usage.md.
 *
 * Grao processo x segmento x modelo — fora de qualquer execucao 00c, sem
 * `feature`/`wave`/`execution_id` por construcao (dec-005).
 *
 * O que se valida (Principio II/III):
 * - base v2-v12 (tabela ausente) -> `hasLooseUsage` false, byProject/byModel
 *   vazios, coverage/comparison com todos os campos null (nunca 0 fabricado);
 * - `sum()` sem coalesce: NULL do SQLite permanece NULL, nunca vira 0;
 * - ordenacao por `costUsd` desc, NULL por ultimo;
 * - binding parametrizado (`project` via `?`, nunca interpolacao);
 * - `model IS NULL` vira `'(desconhecido)'`, nunca descartado; cardinalidade
 *   acima do limite vira `'(outros)'` com soma tolerante a NULL;
 * - segmentos ABERTOS contados separadamente (valor parcial sinalizavel);
 * - comparison: agregacao lado a lado avulso x pipeline (nunca join linha a
 *   linha); base sem `wave_model_usage` degrada o lado pipeline para null;
 * - blendedCostPerMtok: null quando tokens 0/NULL (divisao indefinida nunca
 *   vira 0) — formula SUM(cost)/SUM(tokens)*1e6 do data-model.md.
 */
import { describe, it, expect, afterEach } from 'vitest';
import { mkdtempSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import Database from 'better-sqlite3';
import {
  getLooseUsage,
  getLooseUsageByProject,
  getLooseUsageByModel,
  getLooseUsageComparison,
  getLooseUsageCoverage,
  MODEL_USAGE_LIMIT,
  MODEL_USAGE_OTHERS_LABEL,
  MODEL_USAGE_UNKNOWN_LABEL,
} from '../../src/db/queries/metrics.js';
import { hasLooseUsage } from '../../src/db/queries/waves.js';

const toClean: string[] = [];
afterEach(() => {
  for (const f of toClean) {
    for (const suffix of ['', '-shm', '-wal']) {
      try { unlinkSync(f + suffix); } catch { /* ignorar */ }
    }
  }
  toClean.length = 0;
});

// DDL identica a `recall_schema_ddl` do cstk 6.6.0 (cli/lib/recall.sh).
const LOOSE_USAGE_V13 = `
CREATE TABLE loose_usage (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  project_path TEXT,
  process_key TEXT NOT NULL,
  segment_id TEXT NOT NULL,
  model TEXT,
  cost_usd REAL,
  total_tokens INTEGER,
  segment_open INTEGER,
  captured_at TEXT NOT NULL,
  ingested_at TEXT NOT NULL,
  UNIQUE(process_key, segment_id, model)
);`;

const WAVE_MODEL_USAGE_V12 = `
CREATE TABLE wave_model_usage (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL, feature TEXT NOT NULL, wave TEXT NOT NULL,
  execution_id TEXT NOT NULL, source_ts TEXT NOT NULL, source_id TEXT NOT NULL,
  model TEXT, cost_usd REAL, total_tokens INTEGER,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);`;

function mkDb(ddl: string): Database.Database {
  const f = join(mkdtempSync(join(tmpdir(), 'loose-usage-')), 'k.db');
  toClean.push(f);
  const db = new Database(f);
  db.exec(ddl);
  return db;
}

let seq = 0;
function insertLoose(db: Database.Database, cols: Record<string, unknown>): void {
  seq += 1;
  const base = {
    project: 'p', project_path: '/tmp/p', process_key: 'pk1',
    segment_id: `seg-${String(seq).padStart(3, '0')}`, model: 'claude-sonnet-5',
    cost_usd: null, total_tokens: null, segment_open: 0,
    captured_at: '2026-08-07T00:00:00Z', ingested_at: 't', ...cols,
  };
  const keys = Object.keys(base);
  db.prepare(
    `INSERT INTO loose_usage(${keys.join(',')}) VALUES(${keys.map(k => '@' + k).join(',')})`,
  ).run(base);
}

function insertPipeline(db: Database.Database, cols: Record<string, unknown>): void {
  seq += 1;
  const base = {
    project: 'p', feature: 'f', wave: `onda-${seq}`, execution_id: 'e',
    source_ts: '2026-08-07T00:00:00Z', source_id: `s${seq}`, ingested_at: 't', ...cols,
  };
  const keys = Object.keys(base);
  db.prepare(
    `INSERT INTO wave_model_usage(${keys.join(',')}) VALUES(${keys.map(k => '@' + k).join(',')})`,
  ).run(base);
}

describe('hasLooseUsage — sonda de tabela', () => {
  it('true quando a tabela existe', () => {
    expect(hasLooseUsage(mkDb(LOOSE_USAGE_V13))).toBe(true);
  });

  it('false quando a tabela nao existe (base v2-v12)', () => {
    expect(hasLooseUsage(mkDb(WAVE_MODEL_USAGE_V12))).toBe(false);
  });
});

describe('getLooseUsageByProject — agregacao e NULL', () => {
  it('tabela ausente: vazio, sem lancar (Principio II)', () => {
    expect(getLooseUsageByProject(mkDb(WAVE_MODEL_USAGE_V12))).toEqual([]);
  });

  it('agrega custo/tokens/segmentos/processos por projeto, sem coalesce', () => {
    const db = mkDb(LOOSE_USAGE_V13);
    insertLoose(db, { project: 'proj-a', process_key: 'pk1', segment_id: 'seg-001', cost_usd: 1.5, total_tokens: 1000 });
    insertLoose(db, { project: 'proj-a', process_key: 'pk1', segment_id: 'seg-002', cost_usd: 0.5, total_tokens: 200, segment_open: 1 });
    insertLoose(db, { project: 'proj-a', process_key: 'pk2', segment_id: 'seg-001', model: 'claude-haiku-4-5', cost_usd: null, total_tokens: null });
    const rows = getLooseUsageByProject(db);
    expect(rows).toHaveLength(1);
    const r = rows[0]!;
    expect(r.project).toBe('proj-a');
    expect(r.costUsd).toBeCloseTo(2.0, 6);
    expect(r.totalTokens).toBe(1200);
    expect(r.processes).toBe(2);
    expect(r.segments).toBe(3); // pk1/seg-001, pk1/seg-002, pk2/seg-001
    expect(r.openSegments).toBe(1);
  });

  it('projeto sem NENHUMA medicao: costUsd/totalTokens null, nunca 0', () => {
    const db = mkDb(LOOSE_USAGE_V13);
    insertLoose(db, { project: 'proj-a', cost_usd: null, total_tokens: null });
    const rows = getLooseUsageByProject(db);
    expect(rows[0]?.costUsd).toBeNull();
    expect(rows[0]?.totalTokens).toBeNull();
  });

  it('ordena por costUsd desc, NULL por ultimo', () => {
    const db = mkDb(LOOSE_USAGE_V13);
    insertLoose(db, { project: 'proj-null', cost_usd: null });
    insertLoose(db, { project: 'proj-big', process_key: 'pk2', cost_usd: 10 });
    insertLoose(db, { project: 'proj-small', process_key: 'pk3', cost_usd: 1 });
    expect(getLooseUsageByProject(db).map(r => r.project)).toEqual(['proj-big', 'proj-small', 'proj-null']);
  });

  it('binding parametrizado: filtro por project nao vaza outros projetos', () => {
    const db = mkDb(LOOSE_USAGE_V13);
    insertLoose(db, { project: 'proj-a', cost_usd: 1.0 });
    insertLoose(db, { project: 'proj-b', process_key: 'pk2', cost_usd: 99.0 });
    const rows = getLooseUsageByProject(db, { project: 'proj-a' });
    expect(rows).toHaveLength(1);
    expect(rows[0]?.costUsd).toBeCloseTo(1.0, 6);
  });
});

describe('getLooseUsageByModel — rotulos e cardinalidade', () => {
  it('model IS NULL vira (desconhecido), nunca descartado', () => {
    const db = mkDb(LOOSE_USAGE_V13);
    insertLoose(db, { model: null, cost_usd: 3.0, total_tokens: 500 });
    const rows = getLooseUsageByModel(db);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.model).toBe(MODEL_USAGE_UNKNOWN_LABEL);
    expect(rows[0]?.costUsd).toBeCloseTo(3.0, 6);
  });

  it('agrega o mesmo modelo atraves de segmentos e ordena por custo', () => {
    const db = mkDb(LOOSE_USAGE_V13);
    insertLoose(db, { segment_id: 'seg-001', model: 'claude-sonnet-5', cost_usd: 1.0, total_tokens: 100 });
    insertLoose(db, { segment_id: 'seg-002', model: 'claude-sonnet-5', cost_usd: 2.0, total_tokens: 200 });
    insertLoose(db, { segment_id: 'seg-001', model: 'claude-fable-5', cost_usd: 9.0, total_tokens: 50 });
    const rows = getLooseUsageByModel(db);
    expect(rows.map(r => r.model)).toEqual(['claude-fable-5', 'claude-sonnet-5']);
    expect(rows[1]?.costUsd).toBeCloseTo(3.0, 6);
    expect(rows[1]?.totalTokens).toBe(300);
    expect(rows[1]?.segments).toBe(2);
  });

  it("cardinalidade acima do limite vira '(outros)' com soma tolerante a NULL", () => {
    const db = mkDb(LOOSE_USAGE_V13);
    for (let i = 12; i >= 1; i--) {
      insertLoose(db, { segment_id: `seg-${i}`, model: `model-${i}`, cost_usd: i, total_tokens: i * 100 });
    }
    const rows = getLooseUsageByModel(db);
    expect(rows).toHaveLength(MODEL_USAGE_LIMIT + 1);
    const outros = rows[rows.length - 1]!;
    expect(outros.model).toBe(MODEL_USAGE_OTHERS_LABEL);
    expect(outros.costUsd).toBeCloseTo(3.0, 6); // modelos 1 e 2
    expect(outros.totalTokens).toBe(300);
  });
});

describe('getLooseUsageComparison — avulso x pipeline (FR-009)', () => {
  it('tabela loose_usage ausente: os dois lados 3x null', () => {
    const db = mkDb(WAVE_MODEL_USAGE_V12);
    insertPipeline(db, { model: 'claude-sonnet-5', cost_usd: 5.0, total_tokens: 100 });
    expect(getLooseUsageComparison(db)).toEqual({
      loose: { costUsd: null, totalTokens: null, blendedCostPerMtok: null },
      pipeline: { costUsd: null, totalTokens: null, blendedCostPerMtok: null },
    });
  });

  it('base sem wave_model_usage: lado pipeline 3x null, lado avulso medido', () => {
    const db = mkDb(LOOSE_USAGE_V13);
    insertLoose(db, { cost_usd: 2.0, total_tokens: 1_000_000 });
    const c = getLooseUsageComparison(db);
    expect(c.loose.costUsd).toBeCloseTo(2.0, 6);
    expect(c.loose.blendedCostPerMtok).toBeCloseTo(2.0, 6);
    expect(c.pipeline).toEqual({ costUsd: null, totalTokens: null, blendedCostPerMtok: null });
  });

  it('agrega os dois lados no mesmo recorte de projeto', () => {
    const db = mkDb(LOOSE_USAGE_V13 + WAVE_MODEL_USAGE_V12);
    insertLoose(db, { project: 'proj-a', cost_usd: 1.0, total_tokens: 500_000 });
    insertLoose(db, { project: 'proj-b', process_key: 'pk2', cost_usd: 50.0, total_tokens: 10 });
    insertPipeline(db, { project: 'proj-a', model: 'claude-sonnet-5', cost_usd: 4.0, total_tokens: 2_000_000 });
    const c = getLooseUsageComparison(db, { project: 'proj-a' });
    expect(c.loose.costUsd).toBeCloseTo(1.0, 6);
    expect(c.loose.blendedCostPerMtok).toBeCloseTo(2.0, 6);
    expect(c.pipeline.costUsd).toBeCloseTo(4.0, 6);
    expect(c.pipeline.blendedCostPerMtok).toBeCloseTo(2.0, 6);
  });

  it('blendedCostPerMtok: null quando tokens 0 ou NULL (nunca 0 fabricado)', () => {
    const db = mkDb(LOOSE_USAGE_V13);
    insertLoose(db, { segment_id: 'seg-001', cost_usd: 1.0, total_tokens: 0 });
    const c0 = getLooseUsageComparison(db);
    expect(c0.loose.costUsd).toBeCloseTo(1.0, 6);
    expect(c0.loose.totalTokens).toBe(0); // zero MEDIDO preservado
    expect(c0.loose.blendedCostPerMtok).toBeNull();

    const db2 = mkDb(LOOSE_USAGE_V13);
    insertLoose(db2, { cost_usd: 1.0, total_tokens: null });
    expect(getLooseUsageComparison(db2).loose.blendedCostPerMtok).toBeNull();
  });
});

describe('getLooseUsageCoverage — contadores da amostra', () => {
  it('tabela ausente: todos os campos null, nunca 0', () => {
    expect(getLooseUsageCoverage(mkDb(WAVE_MODEL_USAGE_V12))).toEqual({
      rowsTotal: null, segmentsTotal: null, segmentsOpen: null,
      processes: null, projects: null, lastCapturedAt: null,
    });
  });

  it('tabela presente e vazia: contagens 0 legitimas (opt-in desligado)', () => {
    const c = getLooseUsageCoverage(mkDb(LOOSE_USAGE_V13));
    expect(c.rowsTotal).toBe(0);
    expect(c.segmentsTotal).toBe(0);
    expect(c.lastCapturedAt).toBeNull();
  });

  it('conta segmentos abertos separado do total', () => {
    const db = mkDb(LOOSE_USAGE_V13);
    insertLoose(db, { segment_id: 'seg-001', segment_open: 0 });
    insertLoose(db, { segment_id: 'seg-002', segment_open: 1, captured_at: '2026-08-07T10:00:00Z' });
    const c = getLooseUsageCoverage(db);
    expect(c.rowsTotal).toBe(2);
    expect(c.segmentsTotal).toBe(2);
    expect(c.segmentsOpen).toBe(1);
    expect(c.processes).toBe(1);
    expect(c.projects).toBe(1);
    expect(c.lastCapturedAt).toBe('2026-08-07T10:00:00Z');
  });
});

describe('getLooseUsage — agregador do endpoint', () => {
  it('combina os 4 recortes num unico LooseUsageResult', () => {
    const db = mkDb(LOOSE_USAGE_V13 + WAVE_MODEL_USAGE_V12);
    insertLoose(db, { cost_usd: 1.0, total_tokens: 10 });
    insertPipeline(db, { model: 'claude-sonnet-5', cost_usd: 2.0, total_tokens: 20 });
    const r = getLooseUsage(db);
    expect(r.byProject).toHaveLength(1);
    expect(r.byModel).toHaveLength(1);
    expect(r.comparison.loose.costUsd).toBeCloseTo(1.0, 6);
    expect(r.comparison.pipeline.costUsd).toBeCloseTo(2.0, 6);
    expect(r.coverage.rowsTotal).toBe(1);
  });

  it('tabela ausente: shape vazio inteiro (arrays [], coverage/comparison null)', () => {
    const r = getLooseUsage(mkDb(WAVE_MODEL_USAGE_V12));
    expect(r).toEqual({
      byProject: [],
      byModel: [],
      comparison: {
        loose: { costUsd: null, totalTokens: null, blendedCostPerMtok: null },
        pipeline: { costUsd: null, totalTokens: null, blendedCostPerMtok: null },
      },
      coverage: {
        rowsTotal: null, segmentsTotal: null, segmentsOpen: null,
        processes: null, projects: null, lastCapturedAt: null,
      },
    });
  });
});
