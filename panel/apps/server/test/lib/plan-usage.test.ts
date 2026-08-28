/**
 * Gauge do PLANO (schema v14 — cstk 7.2.0, `plan_usage`).
 * Ref: ../cstk/docs/specs/plan-usage-capture/data-model.md.
 *
 * Grao escopo x momento de captura, append-only, fora de qualquer execucao 00c
 * (sem `feature`/`wave`/`execution_id` por construcao — mesma familia de
 * `loose_usage`). NAO e custo nem token: e o percentual do plano ja consumido
 * em duas janelas independentes.
 *
 * O que se valida (Principio II/III):
 * - base v2-v13 (tabela ausente) -> `hasPlanUsage` false, byScope/series
 *   vazios, coverage com TODOS os campos null (nunca 0 fabricado);
 * - tabela presente e VAZIA -> coverage com contagens 0 legitimas: a captura e
 *   opt-in, "sem linha" e "sem medicao", jamais "plano em 0%";
 * - estado corrente por escopo vem do maior `id` (append-only), nao do
 *   `captured_at` — duas capturas podem cair no mesmo segundo ISO;
 * - `five_hour` e `seven_day` NUNCA se misturam: series distintas (FR-005);
 * - `used_percentage` NULL na origem sobe NULL, nao 0 (ausencia parcial);
 * - `used_percentage` = 0 REAL sobrevive como 0 e nao vira null;
 * - `resets_at` permanece epoch em SEGUNDOS, sem conversao na borda;
 * - o corte da serie guarda os pontos mais RECENTES e sinaliza truncamento.
 */
import { describe, it, expect, afterEach } from 'vitest';
import { mkdtempSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import Database from 'better-sqlite3';
import {
  getPlanUsage,
  getPlanUsageByScope,
  getPlanUsageSeries,
  getPlanUsageCoverage,
} from '../../src/db/queries/metrics.js';
import { hasPlanUsage } from '../../src/db/queries/waves.js';

const toClean: string[] = [];
afterEach(() => {
  for (const f of toClean) {
    for (const suffix of ['', '-shm', '-wal']) {
      try { unlinkSync(f + suffix); } catch { /* ignorar */ }
    }
  }
  toClean.length = 0;
});

// DDL identica a `recall_schema_ddl` do cstk 7.2.0 (cli/lib/recall.sh), CHECK
// de escopo incluso — se o cstk mudar o dominio, o teste quebra aqui.
const PLAN_USAGE_V14 = `
CREATE TABLE plan_usage (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  project_path TEXT,
  session_id TEXT NOT NULL,
  scope TEXT NOT NULL CHECK (scope IN ('five_hour','seven_day')),
  used_percentage REAL,
  resets_at INTEGER,
  captured_at TEXT NOT NULL,
  ingested_at TEXT NOT NULL
);`;

function mkDb(ddl: string): Database.Database {
  const f = join(mkdtempSync(join(tmpdir(), 'plan-usage-')), 'k.db');
  toClean.push(f);
  const db = new Database(f);
  db.exec(ddl);
  return db;
}

function insertPlan(db: Database.Database, cols: Record<string, unknown>): void {
  const base = {
    project: 'p', project_path: '/tmp/p', session_id: 'sess-1',
    scope: 'five_hour', used_percentage: 12.5, resets_at: 1786000000,
    captured_at: '2026-08-10T12:00:00Z', ingested_at: '2026-08-10T12:00:00Z',
    ...cols,
  };
  db.prepare(`
    INSERT INTO plan_usage
      (project, project_path, session_id, scope, used_percentage, resets_at, captured_at, ingested_at)
    VALUES (@project, @project_path, @session_id, @scope, @used_percentage, @resets_at, @captured_at, @ingested_at)
  `).run(base);
}

// ─── Base sem a tabela (v2-v13) ───────────────────────────────────────────────

describe('plan-usage — base sem a tabela (v2-v13)', () => {
  it('hasPlanUsage=false e todos os recortes degradam sem lancar', () => {
    const db = mkDb('CREATE TABLE waves (id INTEGER PRIMARY KEY);');
    expect(hasPlanUsage(db)).toBe(false);

    const result = getPlanUsage(db);
    expect(result.byScope).toEqual([]);
    expect(result.series).toEqual([]);
    expect(result.seriesTruncated).toBe(false);
    // TODOS null, nunca 0 — "tabela ausente" nao pode virar "plano zerado".
    expect(result.coverage.rowsTotal).toBeNull();
    expect(result.coverage.scopes).toBeNull();
    expect(result.coverage.sessions).toBeNull();
    expect(result.coverage.lastCapturedAt).toBeNull();
    db.close();
  });
});

// ─── Tabela presente e vazia (captura opt-in desligada) ───────────────────────

describe('plan-usage — tabela presente e vazia', () => {
  it('distingue "sem medicao" (0 legitimo) de "tabela ausente" (null)', () => {
    const db = mkDb(PLAN_USAGE_V14);
    expect(hasPlanUsage(db)).toBe(true);

    const result = getPlanUsage(db);
    expect(result.byScope).toEqual([]);
    // Contagem 0 aqui e REAL: a tabela existe e nao tem linha. E o unico jeito
    // de a UI dizer "captura nao ligada" em vez de "base velha".
    expect(result.coverage.rowsTotal).toBe(0);
    expect(result.coverage.scopes).toBe(0);
    expect(result.coverage.firstCapturedAt).toBeNull();
    db.close();
  });
});

// ─── Estado corrente por escopo ───────────────────────────────────────────────

describe('plan-usage — estado corrente por escopo', () => {
  it('os dois escopos ficam separados, cada um com seu ultimo valor', () => {
    const db = mkDb(PLAN_USAGE_V14);
    insertPlan(db, { scope: 'five_hour', used_percentage: 10, captured_at: '2026-08-10T10:00:00Z' });
    insertPlan(db, { scope: 'seven_day', used_percentage: 40, captured_at: '2026-08-10T10:00:00Z' });
    insertPlan(db, { scope: 'five_hour', used_percentage: 55.5, captured_at: '2026-08-10T11:00:00Z' });
    insertPlan(db, { scope: 'seven_day', used_percentage: 43, captured_at: '2026-08-10T11:00:00Z' });

    const byScope = getPlanUsageByScope(db);
    expect(byScope).toHaveLength(2);
    const five = byScope.find(s => s.scope === 'five_hour');
    const seven = byScope.find(s => s.scope === 'seven_day');
    // Janelas independentes: 55.5% da janela de 5h convive com 43% da de 7d.
    // Somar/mediar as duas nao produziria numero com significado.
    expect(five?.usedPercentage).toBe(55.5);
    expect(seven?.usedPercentage).toBe(43);
    expect(five?.captures).toBe(2);
    expect(seven?.captures).toBe(2);
    db.close();
  });

  it('"corrente" vem do maior id, nao do captured_at (empate no mesmo segundo)', () => {
    const db = mkDb(PLAN_USAGE_V14);
    const mesmoSegundo = '2026-08-10T12:00:00Z';
    insertPlan(db, { scope: 'five_hour', used_percentage: 20, captured_at: mesmoSegundo });
    insertPlan(db, { scope: 'five_hour', used_percentage: 30, captured_at: mesmoSegundo });

    const [five] = getPlanUsageByScope(db);
    // Ordenar por captured_at deixaria o resultado ao acaso do planner.
    expect(five?.usedPercentage).toBe(30);
    db.close();
  });

  it('pico do recorte e o MAIOR observado, nao o ultimo', () => {
    const db = mkDb(PLAN_USAGE_V14);
    insertPlan(db, { scope: 'five_hour', used_percentage: 90, captured_at: '2026-08-10T10:00:00Z' });
    // Reset da janela derruba o corrente; o pico da janela precisa sobreviver.
    insertPlan(db, { scope: 'five_hour', used_percentage: 3, captured_at: '2026-08-10T15:00:00Z' });

    const [five] = getPlanUsageByScope(db);
    expect(five?.usedPercentage).toBe(3);
    expect(five?.peakUsedPercentage).toBe(90);
    db.close();
  });

  it('used_percentage NULL na origem sobe NULL — 0% medido sobe 0', () => {
    const db = mkDb(PLAN_USAGE_V14);
    // Ausencia PARCIAL: escopo presente no payload, campo ausente dentro dele.
    insertPlan(db, { scope: 'five_hour', used_percentage: null, resets_at: null });
    insertPlan(db, { scope: 'seven_day', used_percentage: 0 });

    const byScope = getPlanUsageByScope(db);
    const five = byScope.find(s => s.scope === 'five_hour');
    const seven = byScope.find(s => s.scope === 'seven_day');
    expect(five?.usedPercentage).toBeNull();
    expect(five?.resetsAt).toBeNull();
    // 0 medido NAO pode virar null: sao afirmacoes diferentes sobre o plano.
    expect(seven?.usedPercentage).toBe(0);
    db.close();
  });

  it('resets_at permanece epoch em SEGUNDOS, sem conversao na borda', () => {
    const db = mkDb(PLAN_USAGE_V14);
    insertPlan(db, { scope: 'five_hour', resets_at: 1786000000 });
    const [five] = getPlanUsageByScope(db);
    // Multiplicar por 1000 na query mataria a distincao com captured_at.
    expect(five?.resetsAt).toBe(1786000000);
    db.close();
  });
});

// ─── Serie temporal ───────────────────────────────────────────────────────────

describe('plan-usage — serie temporal', () => {
  it('ordena por escopo e depois cronologicamente (ordem de plotagem)', () => {
    const db = mkDb(PLAN_USAGE_V14);
    insertPlan(db, { scope: 'five_hour', used_percentage: 30, captured_at: '2026-08-10T11:00:00Z' });
    insertPlan(db, { scope: 'five_hour', used_percentage: 10, captured_at: '2026-08-10T09:00:00Z' });
    insertPlan(db, { scope: 'seven_day', used_percentage: 40, captured_at: '2026-08-10T10:00:00Z' });

    const { points, truncated } = getPlanUsageSeries(db);
    expect(truncated).toBe(false);
    expect(points.map(p => `${p.scope}@${p.usedPercentage}`)).toEqual([
      'five_hour@10', 'five_hour@30', 'seven_day@40',
    ]);
    db.close();
  });

  it('corte guarda os pontos mais RECENTES e sinaliza truncamento', () => {
    const db = mkDb(PLAN_USAGE_V14);
    for (let i = 1; i <= 5; i++) {
      insertPlan(db, {
        scope: 'five_hour',
        used_percentage: i * 10,
        captured_at: `2026-08-10T1${i}:00:00Z`,
      });
    }
    const { points, truncated } = getPlanUsageSeries(db, {}, 2);
    expect(truncated).toBe(true);
    // Os dois ultimos (40, 50), nao os dois primeiros: a janela que interessa
    // e a atual. Truncar nunca pode virar "sem dado".
    expect(points.map(p => p.usedPercentage)).toEqual([40, 50]);
    db.close();
  });
});

// ─── Cobertura ────────────────────────────────────────────────────────────────

describe('plan-usage — cobertura', () => {
  it('conta escopos, sessoes e projetos distintos + extremos da janela', () => {
    const db = mkDb(PLAN_USAGE_V14);
    insertPlan(db, { scope: 'five_hour', session_id: 's1', project: 'a', captured_at: '2026-08-10T09:00:00Z' });
    insertPlan(db, { scope: 'seven_day', session_id: 's1', project: 'a', captured_at: '2026-08-10T09:00:00Z' });
    insertPlan(db, { scope: 'five_hour', session_id: 's2', project: 'b', captured_at: '2026-08-10T13:00:00Z' });

    const cov = getPlanUsageCoverage(db);
    expect(cov.rowsTotal).toBe(3);
    expect(cov.scopes).toBe(2);
    expect(cov.sessions).toBe(2);
    expect(cov.projects).toBe(2);
    expect(cov.firstCapturedAt).toBe('2026-08-10T09:00:00Z');
    expect(cov.lastCapturedAt).toBe('2026-08-10T13:00:00Z');
    db.close();
  });
});
