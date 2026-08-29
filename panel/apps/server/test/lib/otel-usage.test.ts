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
import { getOtelUsage, getOtelCostOverTime } from '../../src/db/queries/metrics.js';
import { hasOtelUsage, hasOtelBreakdown, listWavesByExecution } from '../../src/db/queries/waves.js';
import { mapWave } from '../../src/mappers/wave.js';

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

// ---------------------------------------------------------------------------
// Projecao por onda (listWavesByExecution) — o dado v11 tem que chegar na
// TABELA de ondas, nao so no agregado. Sem isto o painel some com o custo
// justamente onde ele e acionavel: a onda cara.
// ---------------------------------------------------------------------------

/** `waves` completa v11 — o que `cstk recall` cria a partir da 5.30.0. */
const WAVES_FULL_V11 = `
CREATE TABLE waves (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL, feature TEXT NOT NULL, wave TEXT NOT NULL,
  execution_id TEXT NOT NULL, source_ts TEXT NOT NULL, source_id TEXT NOT NULL,
  stages TEXT, started_at TEXT, finished_at TEXT,
  wallclock_seconds INTEGER, tool_calls INTEGER, termination_reason TEXT,
  n_stages INTEGER, n_skills INTEGER, session TEXT,
  otel_cost_usd REAL, otel_cost_main_usd REAL, otel_cost_subagent_usd REAL,
  otel_total_tokens INTEGER, otel_subagent_tokens INTEGER,
  agent_spawns_total INTEGER, agent_spawns_with_usage INTEGER,
  agent_total_tokens INTEGER, agent_input_tokens INTEGER,
  agent_output_tokens INTEGER, agent_cache_read_tokens INTEGER,
  agent_cache_creation_tokens INTEGER, agent_tool_use_count INTEGER,
  agent_duration_ms INTEGER,
  ingested_at TEXT NOT NULL
);`;

/** Mesma tabela sem as 5 colunas v11 — base de quem ainda nao migrou. */
const WAVES_FULL_V10 = WAVES_FULL_V11
  .split('\n')
  .filter(l => !l.includes('otel_'))
  .join('\n');

describe('listWavesByExecution (schema v11)', () => {
  it('projeta as 5 colunas otel e preserva o custo fracionario', () => {
    const db = mkDb(WAVES_FULL_V11);
    insertWave(db, {
      wave: 'onda-001', source_id: 's1', stages: 'plan', started_at: '2026-07-26T10:00:00Z',
      tool_calls: 90, otel_cost_usd: 0.229038, otel_cost_main_usd: 0.130553,
      otel_cost_subagent_usd: 0.098485, otel_total_tokens: 648, otel_subagent_tokens: 648,
    });
    const rows = listWavesByExecution(db, 'e');
    expect(rows).toHaveLength(1);
    expect(rows[0]?.otel_cost_usd).toBeCloseTo(0.229038, 6);
    expect(rows[0]?.otel_cost_subagent_usd).toBeCloseTo(0.098485, 6);
    // e o DTO servido a UI carrega o mesmo numero, sem arredondar
    const dto = mapWave(rows[0]!);
    expect(dto.otelCostUsd).toBeCloseTo(0.229038, 6);
    expect(dto.otelSubagentTokens).toBe(648);
  });

  it('base v10 degrada para null sem "no such column"', () => {
    const db = mkDb(WAVES_FULL_V10);
    insertWave(db, { wave: 'onda-001', source_id: 's1', stages: 'plan', tool_calls: 12 });
    const rows = listWavesByExecution(db, 'e');
    expect(rows).toHaveLength(1);
    expect(rows[0]?.otel_cost_usd).toBeNull();
    expect(rows[0]?.otel_subagent_tokens).toBeNull();
    // toolCalls continua vindo: a coluna nova ausente nao derruba a linha
    expect(rows[0]?.tool_calls).toBe(12);
  });

  it('onda sem telemetria na MESMA execucao fica null, nao zero', () => {
    const db = mkDb(WAVES_FULL_V11);
    insertWave(db, {
      wave: 'onda-001', source_id: 's1', started_at: '2026-07-26T10:00:00Z',
      otel_cost_usd: 0.5, otel_cost_main_usd: 0.3, otel_cost_subagent_usd: 0.2,
    });
    insertWave(db, { wave: 'onda-002', source_id: 's2', started_at: '2026-07-26T11:00:00Z' });
    const rows = listWavesByExecution(db, 'e');
    expect(rows).toHaveLength(2);
    expect(rows[0]?.otel_cost_usd).toBeCloseTo(0.5, 6);
    expect(rows[1]?.otel_cost_usd).toBeNull();
  });
});

describe('getOtelCostOverTime (schema v11)', () => {
  it('agrupa por dia e OMITE dias sem telemetria (nao vira zero)', () => {
    const db = mkDb(WAVES_FULL_V11);
    insertWave(db, {
      wave: 'onda-001', source_id: 's1', started_at: '2026-07-26T10:00:00Z',
      otel_cost_usd: 0.2, otel_cost_main_usd: 0.12, otel_cost_subagent_usd: 0.08,
    });
    insertWave(db, {
      wave: 'onda-002', source_id: 's2', started_at: '2026-07-26T18:00:00Z',
      otel_cost_usd: 0.3, otel_cost_main_usd: 0.18, otel_cost_subagent_usd: 0.12,
    });
    // dia seguinte executou, mas sem telemetria: NAO pode aparecer como $0
    insertWave(db, { wave: 'onda-003', source_id: 's3', started_at: '2026-07-27T09:00:00Z' });
    const rows = getOtelCostOverTime(db);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.day).toBe('2026-07-26');
    expect(rows[0]?.costUsd).toBeCloseTo(0.5, 6);
    expect(rows[0]?.wavesWithOtel).toBe(2);
  });

  it('base v10 devolve serie vazia (sem lancar)', () => {
    const db = mkDb(WAVES_FULL_V10);
    insertWave(db, { wave: 'onda-001', source_id: 's1', started_at: '2026-07-26T10:00:00Z' });
    expect(getOtelCostOverTime(db)).toEqual([]);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Breakdown de tokens por FONTE x TIPO (schema v12 — cstk 5.33.0)
//
// As 5 colunas de v11 dizem QUANTO custou; estas 8 dizem DE QUE tipo era o
// token. Sem elas, `otel_total_tokens: 8.7M` de uma onda real se le como 8,7M
// de token novo, quando ~95% e contexto relido de cache — erro de leitura de
// uma ordem de grandeza no custo por onda.
//
// A regra mais importante aqui: main e subagente sao coletas INDEPENDENTES.
// Na base real (v14, 1182 ondas) 257 tem `by_source.subagent` e apenas 27 tem
// `by_source.main`. Um denominador unico de cobertura apresentaria como medido
// um lado que nunca foi coletado.
// ─────────────────────────────────────────────────────────────────────────────

const WAVES_V12 = `
CREATE TABLE waves (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL, feature TEXT NOT NULL, wave TEXT NOT NULL,
  execution_id TEXT NOT NULL, source_ts TEXT NOT NULL, source_id TEXT NOT NULL,
  started_at TEXT, finished_at TEXT,
  otel_cost_usd REAL, otel_cost_main_usd REAL, otel_cost_subagent_usd REAL,
  otel_total_tokens INTEGER, otel_subagent_tokens INTEGER,
  otel_main_input_tokens INTEGER, otel_main_output_tokens INTEGER,
  otel_main_cache_read_tokens INTEGER, otel_main_cache_creation_tokens INTEGER,
  otel_subagent_input_tokens INTEGER, otel_subagent_output_tokens INTEGER,
  otel_subagent_cache_read_tokens INTEGER, otel_subagent_cache_creation_tokens INTEGER,
  ingested_at TEXT NOT NULL
);`;

// Variante com o resto das colunas de `waves` — `listWavesByExecution` projeta
// wallclock_seconds/tool_calls/n_skills sem guarda de coluna.
const WAVES_FULL_V12 = WAVES_FULL_V11.replace(
  '  ingested_at TEXT NOT NULL',
  `  otel_main_input_tokens INTEGER, otel_main_output_tokens INTEGER,
  otel_main_cache_read_tokens INTEGER, otel_main_cache_creation_tokens INTEGER,
  otel_subagent_input_tokens INTEGER, otel_subagent_output_tokens INTEGER,
  otel_subagent_cache_read_tokens INTEGER, otel_subagent_cache_creation_tokens INTEGER,
  ingested_at TEXT NOT NULL`,
);

describe('getOtelUsage — breakdown por fonte (schema v12)', () => {
  it('detecta a capacidade pela coluna otel_main_input_tokens', () => {
    expect(hasOtelBreakdown(mkDb(WAVES_V12))).toBe(true);
    // Base v11 tem custo mas nao tem breakdown — as duas sondas sao distintas.
    expect(hasOtelBreakdown(mkDb(WAVES_V11))).toBe(false);
    expect(hasOtelUsage(mkDb(WAVES_V11))).toBe(true);
  });

  it('base v11 mantem o custo e degrada SO o breakdown para null', () => {
    const db = mkDb(WAVES_V11);
    insertWave(db, { otel_cost_usd: 0.5, otel_total_tokens: 1000 });
    const r = getOtelUsage(db);
    // Gatear as duas coisas juntas apagaria o custo de uma base v11 inteira.
    expect(r.costUsd).toBeCloseTo(0.5, 6);
    expect(r.mainInputTokens).toBeNull();
    expect(r.subagentCacheReadTokens).toBeNull();
    expect(r.wavesWithMainBreakdown).toBeNull();
    expect(r.wavesWithSubagentBreakdown).toBeNull();
  });

  it('soma os 8 campos e conta as DUAS coberturas separadamente', () => {
    const db = mkDb(WAVES_V12);
    // Onda com os dois lados coletados.
    insertWave(db, {
      wave: 'onda-001', source_id: 's1', otel_cost_usd: 1, otel_total_tokens: 100,
      otel_main_input_tokens: 10, otel_main_output_tokens: 20,
      otel_main_cache_read_tokens: 300, otel_main_cache_creation_tokens: 5,
      otel_subagent_input_tokens: 1, otel_subagent_output_tokens: 2,
      otel_subagent_cache_read_tokens: 30, otel_subagent_cache_creation_tokens: 4,
    });
    // Onda so com o lado subagente — caso MAJORITARIO na base real.
    insertWave(db, {
      wave: 'onda-002', source_id: 's2', otel_cost_usd: 2, otel_total_tokens: 200,
      otel_subagent_input_tokens: 9, otel_subagent_output_tokens: 8,
      otel_subagent_cache_read_tokens: 70, otel_subagent_cache_creation_tokens: 6,
    });
    // Onda sem telemetria nenhuma — entra so no denominador total.
    insertWave(db, { wave: 'onda-003', source_id: 's3' });

    const r = getOtelUsage(db);
    expect(r.mainInputTokens).toBe(10);
    expect(r.mainCacheReadTokens).toBe(300);
    expect(r.subagentInputTokens).toBe(10);
    expect(r.subagentCacheReadTokens).toBe(100);
    // Os dois denominadores DIVERGEM — e e isso que a UI precisa mostrar.
    expect(r.wavesWithMainBreakdown).toBe(1);
    expect(r.wavesWithSubagentBreakdown).toBe(2);
    expect(r.wavesTotal).toBe(3);
  });

  it('lado nao coletado permanece null, nunca 0 somado', () => {
    const db = mkDb(WAVES_V12);
    insertWave(db, {
      otel_cost_usd: 1,
      otel_subagent_input_tokens: 5, otel_subagent_output_tokens: 5,
      otel_subagent_cache_read_tokens: 5, otel_subagent_cache_creation_tokens: 5,
    });
    const r = getOtelUsage(db);
    // sum() sobre coluna 100% NULL devolve NULL — "orquestrador nao medido",
    // que e diferente de "orquestrador nao gastou token".
    expect(r.mainInputTokens).toBeNull();
    expect(r.mainOutputTokens).toBeNull();
    expect(r.subagentInputTokens).toBe(5);
    expect(r.wavesWithMainBreakdown).toBe(0);
  });

  it('listWavesByExecution + mapWave levam as 8 colunas ate o DTO', () => {
    const db = mkDb(WAVES_FULL_V12);
    insertWave(db, {
      wave: 'onda-001', source_id: 's1', execution_id: 'e1',
      started_at: '2026-08-09T05:26:06Z',
      otel_total_tokens: 8782315,
      otel_main_input_tokens: 34, otel_main_output_tokens: 11325,
      otel_main_cache_read_tokens: 3709177, otel_main_cache_creation_tokens: 19242,
      otel_subagent_input_tokens: 88, otel_subagent_output_tokens: 25681,
      otel_subagent_cache_read_tokens: 4615562, otel_subagent_cache_creation_tokens: 199184,
    });
    const [row] = listWavesByExecution(db, 'e1');
    const dto = mapWave(row!);
    expect(dto.otelMainCacheReadTokens).toBe(3709177);
    expect(dto.otelSubagentCacheReadTokens).toBe(4615562);
    // Invariante da onda real: cache read domina o total.
    const cacheRead = (dto.otelMainCacheReadTokens ?? 0) + (dto.otelSubagentCacheReadTokens ?? 0);
    expect(cacheRead / (dto.otelTotalTokens ?? 1)).toBeGreaterThan(0.9);
  });

  it('base v11 projeta as 8 colunas como null no DTO (sem "no such column")', () => {
    const db = mkDb(WAVES_FULL_V11);
    insertWave(db, { wave: 'onda-001', source_id: 's1', execution_id: 'e1', otel_cost_usd: 0.5 });
    const [row] = listWavesByExecution(db, 'e1');
    const dto = mapWave(row!);
    expect(dto.otelCostUsd).toBeCloseTo(0.5, 6);
    expect(dto.otelMainInputTokens).toBeNull();
    expect(dto.otelSubagentCacheCreationTokens).toBeNull();
  });
});
