/**
 * Custo/tokens REAIS por modelo (schema v12 — cstk 5.33.0, `wave_model_usage`).
 * Ref: contracts/model-usage-endpoint.md; data-model.md Parte B; tasks.md 2.1/2.2.
 *
 * Grao onda x modelo — distinto de `otel-usage` (grao onda) e de `model-mix`
 * (DERIVADO de `decisions.choice`, sem custo/tokens).
 *
 * O que se valida (Principio II/III):
 * - base v2-v11 (tabela ausente) -> `hasModelUsage` false, byModel/byStage
 *   vazios e os 3 campos de coverage `null` (nunca 0/[] fabricado);
 * - `sum()` sem coalesce: NULL do SQLite permanece NULL, nunca vira 0;
 * - ordenacao por `costUsd` desc, NULL por ultimo (SC-001);
 * - binding parametrizado (`project`/`feature` via `?`, nunca interpolacao);
 * - cardinalidade: acima de `MODEL_USAGE_LIMIT` (10), excedentes viram
 *   `'(outros)'`, com soma tolerante a NULL (nunca 0 fabricado);
 * - `model IS NULL` vira o rotulo `'(desconhecido)'`, nunca descartado;
 * - byStage: junção `wave_model_usage` x `waves` por
 *   `(project, feature, wave, execution_id)` — correlação confirmada
 *   empiricamente (sondagem 48/48 sobre a knowledge.db real, ver
 *   metrics.ts doc de `getModelUsageByStage`), reproduzida aqui de forma
 *   sintética.
 */
import { describe, it, expect, afterEach } from 'vitest';
import { mkdtempSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import Database from 'better-sqlite3';
import {
  getModelUsage,
  getModelUsageByModel,
  getModelUsageByStage,
  getModelUsageCoverage,
  MODEL_USAGE_LIMIT,
  MODEL_USAGE_OTHERS_LABEL,
  MODEL_USAGE_UNKNOWN_LABEL,
} from '../../src/db/queries/metrics.js';
import { hasModelUsage } from '../../src/db/queries/waves.js';

const toClean: string[] = [];
afterEach(() => {
  for (const f of toClean) {
    for (const suffix of ['', '-shm', '-wal']) {
      try { unlinkSync(f + suffix); } catch { /* ignorar */ }
    }
  }
  toClean.length = 0;
});

// `waves` v11 completa (com `stages` + colunas otel) — o que a base real tem
// quando `wave_model_usage` (v12) tambem existe.
const WAVES_V11 = `
CREATE TABLE waves (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL, feature TEXT NOT NULL, wave TEXT NOT NULL,
  execution_id TEXT NOT NULL, source_ts TEXT NOT NULL, source_id TEXT NOT NULL,
  stages TEXT, started_at TEXT, finished_at TEXT,
  otel_cost_usd REAL, otel_cost_main_usd REAL, otel_cost_subagent_usd REAL,
  otel_total_tokens INTEGER, otel_subagent_tokens INTEGER,
  ingested_at TEXT NOT NULL
);`;

// `waves` v10 (sem colunas otel_*) — para exercitar wavesWithOtelCost=null
// quando a base nao tem a capacidade, mesmo com wave_model_usage presente.
const WAVES_V10 = `
CREATE TABLE waves (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL, feature TEXT NOT NULL, wave TEXT NOT NULL,
  execution_id TEXT NOT NULL, source_ts TEXT NOT NULL, source_id TEXT NOT NULL,
  stages TEXT, started_at TEXT, finished_at TEXT,
  ingested_at TEXT NOT NULL
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
  const f = join(mkdtempSync(join(tmpdir(), 'model-usage-')), 'k.db');
  toClean.push(f);
  const db = new Database(f);
  db.exec(ddl);
  return db;
}

function insertWave(db: Database.Database, cols: Record<string, unknown>): void {
  const base = {
    project: 'p', feature: 'f', wave: 'onda-001', execution_id: 'e',
    source_ts: 't', source_id: 's', ingested_at: 't', ...cols,
  };
  const keys = Object.keys(base);
  db.prepare(
    `INSERT INTO waves(${keys.join(',')}) VALUES(${keys.map(k => '@' + k).join(',')})`,
  ).run(base);
}

function insertModelUsage(db: Database.Database, cols: Record<string, unknown>): void {
  const base = {
    project: 'p', feature: 'f', wave: 'onda-001', execution_id: 'e',
    source_ts: 't', source_id: 's1', ingested_at: 't', ...cols,
  };
  const keys = Object.keys(base);
  db.prepare(
    `INSERT INTO wave_model_usage(${keys.join(',')}) VALUES(${keys.map(k => '@' + k).join(',')})`,
  ).run(base);
}

describe('hasModelUsage — sonda de tabela (nao de coluna)', () => {
  it('true quando a tabela existe', () => {
    const db = mkDb(WAVES_V11 + WAVE_MODEL_USAGE_V12);
    expect(hasModelUsage(db)).toBe(true);
  });

  it('false quando a tabela nao existe (base v2-v11)', () => {
    const db = mkDb(WAVES_V11);
    expect(hasModelUsage(db)).toBe(false);
  });
});

describe('getModelUsageByModel — degradacao (Principio II)', () => {
  it('tabela ausente: byModel vazio, sem lancar', () => {
    const db = mkDb(WAVES_V11);
    expect(getModelUsageByModel(db)).toEqual([]);
  });
});

describe('getModelUsageByModel — agregacao, ordenacao e NULL (Invariante 1)', () => {
  it('agrega sum(cost_usd)/sum(total_tokens) por modelo, sem coalesce', () => {
    const db = mkDb(WAVES_V11 + WAVE_MODEL_USAGE_V12);
    insertModelUsage(db, { source_id: 's1', model: 'claude-sonnet-5', cost_usd: 1.5, total_tokens: 1000 });
    insertModelUsage(db, { source_id: 's2', wave: 'onda-002', model: 'claude-sonnet-5', cost_usd: 2.5, total_tokens: 2000 });
    const rows = getModelUsageByModel(db);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.model).toBe('claude-sonnet-5');
    expect(rows[0]?.costUsd).toBeCloseTo(4.0, 6);
    expect(rows[0]?.totalTokens).toBe(3000);
    expect(rows[0]?.waves).toBe(2);
  });

  it('ordena por costUsd desc, com NULL por ultimo (SC-001)', () => {
    const db = mkDb(WAVES_V11 + WAVE_MODEL_USAGE_V12);
    insertModelUsage(db, { source_id: 's1', model: 'claude-fable-5', cost_usd: 1.0 });
    insertModelUsage(db, { source_id: 's2', model: 'claude-sonnet-5', cost_usd: 10.0 });
    insertModelUsage(db, { source_id: 's3', model: 'claude-opus-5[1m]', cost_usd: null });
    const rows = getModelUsageByModel(db);
    expect(rows.map(r => r.model)).toEqual(['claude-sonnet-5', 'claude-fable-5', 'claude-opus-5[1m]']);
    expect(rows[2]?.costUsd).toBeNull();
  });

  it('model IS NULL vira rotulo (desconhecido), nunca descartado', () => {
    const db = mkDb(WAVES_V11 + WAVE_MODEL_USAGE_V12);
    insertModelUsage(db, { source_id: 's1', model: null, cost_usd: 3.0, total_tokens: 500 });
    const rows = getModelUsageByModel(db);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.model).toBe(MODEL_USAGE_UNKNOWN_LABEL);
    expect(rows[0]?.costUsd).toBeCloseTo(3.0, 6);
  });

  it('binding parametrizado: filtro por project/feature nao vaza outros projetos', () => {
    const db = mkDb(WAVES_V11 + WAVE_MODEL_USAGE_V12);
    insertModelUsage(db, { source_id: 's1', project: 'proj-a', model: 'claude-sonnet-5', cost_usd: 1.0 });
    insertModelUsage(db, { source_id: 's2', project: 'proj-b', model: 'claude-sonnet-5', cost_usd: 99.0 });
    const rows = getModelUsageByModel(db, { project: 'proj-a' });
    expect(rows).toHaveLength(1);
    expect(rows[0]?.costUsd).toBeCloseTo(1.0, 6);
  });

  it("cardinalidade acima do limite vira bucket '(outros)' somando o restante", () => {
    const db = mkDb(WAVES_V11 + WAVE_MODEL_USAGE_V12);
    // 12 modelos distintos, custo decrescente 12..1 -> top 10 nomeados + 2 no bucket.
    for (let i = 12; i >= 1; i--) {
      insertModelUsage(db, { source_id: `s${i}`, model: `model-${i}`, cost_usd: i, total_tokens: i * 100 });
    }
    const rows = getModelUsageByModel(db);
    expect(rows).toHaveLength(MODEL_USAGE_LIMIT + 1);
    expect(rows[rows.length - 1]?.model).toBe(MODEL_USAGE_OTHERS_LABEL);
    // modelos 1 e 2 (os dois menores) somados: cost 1+2=3, tokens 100+200=300
    expect(rows[rows.length - 1]?.costUsd).toBeCloseTo(3.0, 6);
    expect(rows[rows.length - 1]?.totalTokens).toBe(300);
    expect(rows[rows.length - 1]?.waves).toBe(2);
  });

  it("bucket '(outros)' preserva null quando NENHUM excedente tem medicao", () => {
    const db = mkDb(WAVES_V11 + WAVE_MODEL_USAGE_V12);
    for (let i = 11; i >= 1; i--) {
      insertModelUsage(db, {
        source_id: `s${i}`, model: `model-${i}`,
        cost_usd: i <= 1 ? null : 11 - i + 1, // model-1 (o menor, vai para "outros") sem custo medido
        total_tokens: i <= 1 ? null : (11 - i + 1) * 10,
      });
    }
    const rows = getModelUsageByModel(db);
    expect(rows).toHaveLength(11);
    const outros = rows[rows.length - 1];
    expect(outros?.model).toBe(MODEL_USAGE_OTHERS_LABEL);
    // apenas 1 modelo excedente (model-1), sem medicao -> outros.costUsd NULL, nao 0
    expect(outros?.costUsd).toBeNull();
    expect(outros?.totalTokens).toBeNull();
  });
});

describe('getModelUsageCoverage — 3 denominadores independentes (Decision 3)', () => {
  it('tabela ausente: os 3 campos sao null, nunca 0', () => {
    const db = mkDb(WAVES_V11);
    const c = getModelUsageCoverage(db);
    expect(c).toEqual({ wavesTotal: null, wavesWithModelUsage: null, wavesWithOtelCost: null });
  });

  it('wavesTotal / wavesWithModelUsage / wavesWithOtelCost divergem legitimamente', () => {
    const db = mkDb(WAVES_V11 + WAVE_MODEL_USAGE_V12);
    // onda-001: tem otel_cost_usd E linha em wave_model_usage
    insertWave(db, { wave: 'onda-001', source_id: 'w1', otel_cost_usd: 1.0 });
    insertModelUsage(db, { source_id: 's1', wave: 'onda-001', model: 'claude-sonnet-5', cost_usd: 1.0 });
    // onda-002: tem otel_cost_usd MAS SEM linha em wave_model_usage (o gap real observado em campo)
    insertWave(db, { wave: 'onda-002', source_id: 'w2', otel_cost_usd: 2.0 });
    // onda-003: nenhuma medicao
    insertWave(db, { wave: 'onda-003', source_id: 'w3' });
    const c = getModelUsageCoverage(db);
    expect(c.wavesTotal).toBe(3);
    expect(c.wavesWithModelUsage).toBe(1);
    expect(c.wavesWithOtelCost).toBe(2);
  });

  it('base sem colunas otel_* (v10): wavesWithOtelCost null, nao 0', () => {
    const db = mkDb(WAVES_V10 + WAVE_MODEL_USAGE_V12);
    insertWave(db, { wave: 'onda-001', source_id: 'w1' });
    insertModelUsage(db, { source_id: 's1', wave: 'onda-001', model: 'claude-sonnet-5', cost_usd: 1.0 });
    const c = getModelUsageCoverage(db);
    expect(c.wavesTotal).toBe(1);
    expect(c.wavesWithModelUsage).toBe(1);
    expect(c.wavesWithOtelCost).toBeNull();
  });
});

describe('getModelUsageByStage — junção wave_model_usage x waves (viabilidade confirmada)', () => {
  it('tabela ausente: byStage vazio, sem lancar', () => {
    const db = mkDb(WAVES_V11);
    expect(getModelUsageByStage(db)).toEqual([]);
  });

  it('correlaciona por (project, feature, wave, execution_id) e agrupa por etapa+modelo', () => {
    const db = mkDb(WAVES_V11 + WAVE_MODEL_USAGE_V12);
    insertWave(db, { wave: 'onda-001', source_id: 'w1', stages: 'execute-task' });
    insertModelUsage(db, { source_id: 's1', wave: 'onda-001', model: 'claude-sonnet-5', cost_usd: 5.0, total_tokens: 100 });
    insertWave(db, { wave: 'onda-002', source_id: 'w2', stages: 'plan' });
    insertModelUsage(db, { source_id: 's2', wave: 'onda-002', model: 'claude-sonnet-5', cost_usd: 3.0, total_tokens: 50 });
    const rows = getModelUsageByStage(db);
    expect(rows).toHaveLength(2);
    expect(rows[0]).toEqual({ stage: 'execute-task', model: 'claude-sonnet-5', costUsd: 5.0, totalTokens: 100 });
    expect(rows[1]).toEqual({ stage: 'plan', model: 'claude-sonnet-5', costUsd: 3.0, totalTokens: 50 });
  });

  it("onda sem 'stages' registrado e EXCLUIDA (nunca inventa etapa)", () => {
    const db = mkDb(WAVES_V11 + WAVE_MODEL_USAGE_V12);
    insertWave(db, { wave: 'onda-001', source_id: 'w1', stages: null });
    insertModelUsage(db, { source_id: 's1', wave: 'onda-001', model: 'claude-sonnet-5', cost_usd: 5.0 });
    expect(getModelUsageByStage(db)).toEqual([]);
  });

  it('linha em wave_model_usage sem onda correspondente em waves nao aparece (join estrito)', () => {
    const db = mkDb(WAVES_V11 + WAVE_MODEL_USAGE_V12);
    insertModelUsage(db, { source_id: 's1', wave: 'onda-orfa', model: 'claude-sonnet-5', cost_usd: 5.0 });
    expect(getModelUsageByStage(db)).toEqual([]);
  });
});

describe('getModelUsage — agregador do endpoint', () => {
  it('combina byModel + byStage + coverage num unico ModelUsageResult', () => {
    const db = mkDb(WAVES_V11 + WAVE_MODEL_USAGE_V12);
    insertWave(db, { wave: 'onda-001', source_id: 'w1', stages: 'execute-task', otel_cost_usd: 1.0 });
    insertModelUsage(db, { source_id: 's1', wave: 'onda-001', model: 'claude-sonnet-5', cost_usd: 1.0, total_tokens: 10 });
    const result = getModelUsage(db);
    expect(result.byModel).toHaveLength(1);
    expect(result.byStage).toHaveLength(1);
    expect(result.coverage).toEqual({ wavesTotal: 1, wavesWithModelUsage: 1, wavesWithOtelCost: 1 });
  });

  it('tabela ausente: shape vazio inteiro (byModel/byStage=[], coverage 3x null)', () => {
    const db = mkDb(WAVES_V11);
    const result = getModelUsage(db);
    expect(result).toEqual({
      byModel: [],
      byStage: [],
      coverage: { wavesTotal: null, wavesWithModelUsage: null, wavesWithOtelCost: null },
    });
  });
});
