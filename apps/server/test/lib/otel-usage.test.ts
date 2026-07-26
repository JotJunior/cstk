/**
 * Consumo REAL por onda via telemetria OTel (schema v11 — cstk otel-wave-cost).
 *
 * Fonte INDEPENDENTE de `agent_usage`: aquela vem do hook PostToolUse/Agent,
 * que so enxerga o que o spawn devolve — e o spawn do orquestrador ENVOLVE a
 * onda, entao o consumo dele nunca aparece la. Os contadores OTel sobem a cada
 * requisicao, entao cobrem main + subagent + auxiliary. Medido em campo: o
 * subagente e 43-47% do gasto.
 *
 * O que se valida (Principio III — ausente nunca vira zero):
 * - onda sem otel_usage -> todos os campos null;
 * - custo fracionario preservado como REAL (nao truncado para inteiro);
 * - base v<11 (sem as colunas) degrada para null sem lancar;
 * - a cobertura (wavesWithOtel/wavesTotal) permite a UI rotular a amostra.
 */
import { describe, it, expect, afterEach } from 'vitest';
import { mkdtempSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import Database from 'better-sqlite3';
import { getOtelUsage } from '../../src/db/queries/metrics.js';
import { hasOtelUsage } from '../../src/db/queries/waves.js';

const toClean: string[] = [];
afterEach(() => {
  for (const f of toClean) {
    for (const suffix of ['', '-shm', '-wal']) {
      try { unlinkSync(f + suffix); } catch { /* ignorar */ }
    }
  }
  toClean.length = 0;
});

const WAVES_V11 = `
CREATE TABLE waves (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL, feature TEXT NOT NULL, wave TEXT NOT NULL,
  execution_id TEXT NOT NULL, source_ts TEXT NOT NULL, source_id TEXT NOT NULL,
  started_at TEXT, finished_at TEXT,
  otel_cost_usd REAL, otel_cost_main_usd REAL, otel_cost_subagent_usd REAL,
  otel_total_tokens INTEGER, otel_subagent_tokens INTEGER,
  ingested_at TEXT NOT NULL
);`;

const WAVES_V10 = `
CREATE TABLE waves (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL, feature TEXT NOT NULL, wave TEXT NOT NULL,
  execution_id TEXT NOT NULL, source_ts TEXT NOT NULL, source_id TEXT NOT NULL,
  agent_total_tokens INTEGER, ingested_at TEXT NOT NULL
);`;

function mkDb(ddl: string): Database.Database {
  const f = join(mkdtempSync(join(tmpdir(), 'otel-')), 'k.db');
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

describe('getOtelUsage (schema v11)', () => {
  it('detecta a capacidade pela coluna otel_cost_usd', () => {
    expect(hasOtelUsage(mkDb(WAVES_V11))).toBe(true);
    expect(hasOtelUsage(mkDb(WAVES_V10))).toBe(false);
  });

  it('base v10 degrada para null sem lancar (nao "no such column")', () => {
    const db = mkDb(WAVES_V10);
    insertWave(db, { agent_total_tokens: 500 });
    const r = getOtelUsage(db);
    expect(r.costUsd).toBeNull();
    expect(r.costSubagentUsd).toBeNull();
    expect(r.subagentTokens).toBeNull();
  });

  it('onda sem otel_usage: todos os campos null, jamais zero', () => {
    const db = mkDb(WAVES_V11);
    insertWave(db, {});
    const r = getOtelUsage(db);
    expect(r.costUsd).toBeNull();
    expect(r.costMainUsd).toBeNull();
    expect(r.costSubagentUsd).toBeNull();
    expect(r.totalTokens).toBeNull();
    // a onda existe no recorte, so nao tem medicao
    expect(r.wavesTotal).toBe(1);
    expect(r.wavesWithOtel).toBe(0);
  });

  it('preserva custo fracionario (REAL, nao inteiro truncado)', () => {
    const db = mkDb(WAVES_V11);
    insertWave(db, {
      otel_cost_usd: 0.229038, otel_cost_main_usd: 0.130553,
      otel_cost_subagent_usd: 0.098485,
      otel_total_tokens: 64729, otel_subagent_tokens: 35679,
    });
    const r = getOtelUsage(db);
    expect(r.costUsd).toBeCloseTo(0.229038, 6);
    expect(r.costMainUsd).toBeCloseTo(0.130553, 6);
    expect(r.costSubagentUsd).toBeCloseTo(0.098485, 6);
    expect(r.subagentTokens).toBe(35679);
  });

  it('agrega varias ondas e reporta a cobertura da amostra', () => {
    const db = mkDb(WAVES_V11);
    insertWave(db, {
      wave: 'onda-001', source_id: 's1',
      otel_cost_usd: 1.0, otel_cost_main_usd: 0.6,
      otel_cost_subagent_usd: 0.4, otel_subagent_tokens: 100,
    });
    insertWave(db, {
      wave: 'onda-002', source_id: 's2',
      otel_cost_usd: 2.0, otel_cost_main_usd: 1.2,
      otel_cost_subagent_usd: 0.8, otel_subagent_tokens: 200,
    });
    insertWave(db, { wave: 'onda-003', source_id: 's3' }); // sem medicao
    const r = getOtelUsage(db);
    expect(r.costUsd).toBeCloseTo(3.0, 6);
    expect(r.costSubagentUsd).toBeCloseTo(1.2, 6);
    expect(r.subagentTokens).toBe(300);
    // 2 de 3 ondas medidas — a UI usa isso para rotular a parcialidade
    expect(r.wavesWithOtel).toBe(2);
    expect(r.wavesTotal).toBe(3);
  });
});
