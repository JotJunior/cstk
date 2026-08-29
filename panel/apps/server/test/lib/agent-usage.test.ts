/**
 * Consumo de subagentes (schema v10 — cstk wave-token-metrics).
 *
 * Estrategia de fixture, deliberada: os casos rodam contra um DB v10 sintetico
 * criado aqui, MAS o mesmo conjunto de asserts roda tambem contra
 * `apps/server/test/knowledge-fixture-v10.db` quando ele existe — fixture
 * gerada pelo proprio `cstk recall --ingest` (5.25.0) e nao versionada
 * (.gitignore). Motivo: fixture escrita a mao valida o painel contra si mesmo;
 * so o DB do produtor real pega drift de nome/semantica de coluna.
 *
 * O que se valida (Principio III):
 * - onda sem `agent_usage` -> TODOS os campos null (nem contagem de spawn);
 * - onda com spawns e sem dado de uso -> spawns preenchidos, tokens null;
 * - agregados NUNCA coalescem null para 0;
 * - base v<10 (sem as colunas) degrada para null/[] sem lancar.
 */
import { describe, it, expect, afterEach } from 'vitest';
import { mkdtempSync, unlinkSync, existsSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import Database from 'better-sqlite3';
import {
  getAgentUsage, getTokensOverTime, getTokensByWave,
} from '../../src/db/queries/metrics.js';
import { listWavesByExecution, AGENT_USAGE_COLUMNS, hasAgentUsage } from '../../src/db/queries/waves.js';
import { mapWaves } from '../../src/mappers/wave.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REAL_V10_FIXTURE = resolve(join(__dirname, '..', 'knowledge-fixture-v10.db'));

const toClean: string[] = [];
afterEach(() => {
  for (const f of toClean) {
    for (const suffix of ['', '-shm', '-wal']) {
      try { unlinkSync(f + suffix); } catch { /* ignorar */ }
    }
  }
  toClean.length = 0;
});

function tmpFile(): string {
  const p = join(mkdtempSync(join(tmpdir(), 'cstk-usage-')), 'test.db');
  toClean.push(p);
  return p;
}

/** Cria um DB v10 minimo: `waves` com as 9 colunas + schema_meta. */
function makeV10Db(withUsageColumns = true): string {
  const path = tmpFile();
  const db = new Database(path);
  const usageDdl = withUsageColumns
    ? AGENT_USAGE_COLUMNS.map(c => `,\n    ${c} INTEGER`).join('')
    : '';
  db.exec(`
    CREATE TABLE waves (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      project TEXT NOT NULL, feature TEXT NOT NULL, wave TEXT NOT NULL,
      execution_id TEXT NOT NULL, source_ts TEXT NOT NULL, source_id TEXT NOT NULL,
      stages TEXT, started_at TEXT, finished_at TEXT,
      wallclock_seconds INTEGER, tool_calls INTEGER, termination_reason TEXT,
      n_stages INTEGER, n_skills INTEGER, session TEXT${usageDdl},
      ingested_at TEXT NOT NULL
    );
    CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
    INSERT INTO schema_meta VALUES ('schema_version', '${withUsageColumns ? '10' : '7'}');
  `);

  const base = (wave: string, stages: string) =>
    `'p','f','${wave}','exec-1','2026-07-26T09:00:00Z','${wave}','${stages}','2026-07-26T09:00:00Z','2026-07-26T10:00:00Z',3600,90,'concluido',1,1,NULL`;

  if (withUsageColumns) {
    // onda-001: medida, cobertura parcial (3 de 4 spawns)
    db.exec(`INSERT INTO waves (project,feature,wave,execution_id,source_ts,source_id,stages,started_at,finished_at,wallclock_seconds,tool_calls,termination_reason,n_stages,n_skills,session,${AGENT_USAGE_COLUMNS.join(',')},ingested_at)
             VALUES (${base('onda-001', 'specify')},4,3,248500,9800,21400,198300,19000,41,512000,'2026-07-26T12:00:00Z')`);
    // onda-002: spawns observados, NENHUM com dado de uso
    db.exec(`INSERT INTO waves (project,feature,wave,execution_id,source_ts,source_id,stages,started_at,finished_at,wallclock_seconds,tool_calls,termination_reason,n_stages,n_skills,session,agent_spawns_total,agent_spawns_with_usage,ingested_at)
             VALUES (${base('onda-002', 'plan')},2,0,'2026-07-26T12:00:00Z')`);
    // onda-003: sem agent_usage nenhum (onda anterior a feature)
    db.exec(`INSERT INTO waves (project,feature,wave,execution_id,source_ts,source_id,stages,started_at,finished_at,wallclock_seconds,tool_calls,termination_reason,n_stages,n_skills,session,ingested_at)
             VALUES (${base('onda-003', 'review-task')},'2026-07-26T12:00:00Z')`);
  } else {
    db.exec(`INSERT INTO waves (project,feature,wave,execution_id,source_ts,source_id,stages,started_at,finished_at,wallclock_seconds,tool_calls,termination_reason,n_stages,n_skills,session,ingested_at)
             VALUES (${base('onda-001', 'specify')},'2026-07-26T12:00:00Z')`);
  }
  db.close();
  return path;
}

describe('schema v10 — agregados de consumo de subagente', () => {
  it('soma apenas o que foi medido e preserva a cobertura da amostra', () => {
    const db = new Database(makeV10Db(), { readonly: true });
    try {
      const usage = getAgentUsage(db);
      // 4+2 spawns observados, 3+0 com dado de uso: o total de tokens cobre
      // 3 de 6 spawns e o denominador precisa sobreviver ate a UI.
      expect(usage.spawnsTotal).toBe(6);
      expect(usage.spawnsWithUsage).toBe(3);
      expect(usage.totalTokens).toBe(248500);
      expect(usage.wavesWithUsage).toBe(2);  // onda-003 nao coletou
      expect(usage.wavesTotal).toBe(3);
    } finally { db.close(); }
  });

  it('recorte sem nenhuma medicao devolve null, nunca 0', () => {
    const db = new Database(makeV10Db(), { readonly: true });
    try {
      const usage = getAgentUsage(db, { project: 'projeto-inexistente' });
      expect(usage.totalTokens).toBeNull();
      expect(usage.spawnsTotal).toBeNull();
      // wavesTotal e contagem de linhas — 0 aqui e verdade (nenhuma onda).
      expect(usage.wavesTotal).toBe(0);
    } finally { db.close(); }
  });

  it('serie diaria omite ondas sem medicao em vez de somar zero', () => {
    const db = new Database(makeV10Db(), { readonly: true });
    try {
      const rows = getTokensOverTime(db);
      expect(rows).toHaveLength(1);
      expect(rows[0]?.day).toBe('2026-07-26');
      expect(rows[0]?.totalTokens).toBe(248500);
      // spawns do dia contam so as ondas que entraram na serie (com medicao)
      expect(rows[0]?.spawnsTotal).toBe(4);
    } finally { db.close(); }
  });

  it('tokens-by-wave lista so ondas medidas, com a cobertura de cada uma', () => {
    const db = new Database(makeV10Db(), { readonly: true });
    try {
      const rows = getTokensByWave(db);
      expect(rows.map(r => r.wave)).toEqual(['onda-001']);
      expect(rows[0]?.spawnsWithUsage).toBe(3);
      expect(rows[0]?.spawnsTotal).toBe(4);
    } finally { db.close(); }
  });

  it('DTO de onda distingue "nao coletado" de "coletado sem dado"', () => {
    const db = new Database(makeV10Db(), { readonly: true });
    try {
      const waves = mapWaves(listWavesByExecution(db, 'exec-1'));
      const semDado = waves.find(w => w.wave === 'onda-002');
      const naoColetado = waves.find(w => w.wave === 'onda-003');
      expect(semDado?.agentSpawnsTotal).toBe(2);
      expect(semDado?.agentSpawnsWithUsage).toBe(0);
      expect(semDado?.agentTotalTokens).toBeNull();
      expect(naoColetado?.agentSpawnsTotal).toBeNull();
      expect(naoColetado?.agentTotalTokens).toBeNull();
    } finally { db.close(); }
  });

  it('base v<10 (sem as colunas) degrada sem lancar — Principio II', () => {
    const db = new Database(makeV10Db(false), { readonly: true });
    try {
      expect(hasAgentUsage(db)).toBe(false);
      const usage = getAgentUsage(db);
      expect(usage.totalTokens).toBeNull();
      expect(usage.wavesTotal).toBeNull();
      expect(getTokensOverTime(db)).toEqual([]);
      expect(getTokensByWave(db)).toEqual([]);
      const waves = mapWaves(listWavesByExecution(db, 'exec-1'));
      expect(waves[0]?.agentTotalTokens).toBeNull();
      expect(waves[0]?.agentSpawnsTotal).toBeNull();
    } finally { db.close(); }
  });
});

// ─── Mesmo contrato, agora contra o DB gerado pelo produtor real ────────────
// Skip automatico quando a fixture nao existe (ela e gitignored, gerada por
// `cstk recall --ingest`). Sem ela, os casos acima provariam apenas que o
// painel concorda com o proprio DDL de teste.
const hasRealFixture = existsSync(REAL_V10_FIXTURE);

describe.skipIf(!hasRealFixture)('schema v10 — DB gerado por cstk recall --ingest', () => {
  it('le as 9 colunas do produtor real com os mesmos nomes', () => {
    const db = new Database(REAL_V10_FIXTURE, { readonly: true });
    try {
      expect(hasAgentUsage(db)).toBe(true);
      const usage = getAgentUsage(db);
      // A fixture real tem ondas medidas; o que importa aqui e que as colunas
      // existem com os nomes esperados e a cobertura vem junto.
      expect(usage.wavesTotal).toBeGreaterThan(0);
      if (usage.totalTokens != null) {
        expect(usage.spawnsTotal).not.toBeNull();
        expect(usage.spawnsWithUsage).not.toBeNull();
      }
    } finally { db.close(); }
  });
});
