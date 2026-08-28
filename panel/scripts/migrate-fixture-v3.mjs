/**
 * Migra a fixture de teste (apps/server/test/knowledge-fixture.db) de schema v2
 * para v3, de forma DETERMINÍSTICA e idempotente — sem depender da versão da
 * base real da máquina do desenvolvedor. Ref: spec.md FR-V3-010.
 *
 * v3 = `tasks.titulo` (ALTER) + eventos `recall_consulted` + schema_version='3'.
 *
 * Reutilizado por create-fixture.mjs (após a cópia) para garantir que a fixture
 * de integração esteja SEMPRE em v3 — assim os testes (roundtrip 7.1.3 etc.) são
 * reprodutíveis mesmo quando a base de origem ainda está em v2.
 *
 * Uso standalone: node scripts/migrate-fixture-v3.mjs
 */
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

/**
 * Aplica a migração v2→v3 numa conexão better-sqlite3 ABERTA EM ESCRITA.
 * Idempotente. Retorna um resumo { schemaVersion, recallConsulted, titulos }.
 */
export function migrateFixtureToV3(db, { log = console.log } = {}) {
  // 1. tasks.titulo (idempotente)
  const cols = db.pragma('table_info(tasks)').map((r) => r.name);
  if (!cols.includes('titulo')) {
    db.exec('ALTER TABLE tasks ADD COLUMN titulo TEXT');
    log('OK: coluna tasks.titulo adicionada');
  } else {
    log('skip: tasks.titulo ja existe');
  }

  // 2. Popular titulo sintetico nas tasks sem valor (deterministico por wave/feature)
  const updated = db.prepare(`
    UPDATE tasks
    SET titulo = 'Task ' || wave || ' — ' || feature
    WHERE titulo IS NULL OR titulo = ''
  `).run();
  log(`OK: ${updated.changes} titulos populados`);

  // 3. Eventos recall_consulted — 1 produtiva (hits=3) + 1 vazia (hits=0),
  //    ancorados numa execucao existente da fixture.
  const anchor = db.prepare(`
    SELECT project, feature, wave, execucao_id, ingested_at
    FROM events ORDER BY rowid LIMIT 1
  `).get() ?? db.prepare(`
    SELECT project, feature, wave, execucao_id, ingested_at
    FROM tasks ORDER BY rowid LIMIT 1
  `).get();

  if (!anchor) throw new Error('fixture sem events/tasks para ancorar recall_consulted');

  const insEvent = db.prepare(`
    INSERT INTO events
      (project, feature, wave, execucao_id, source_ts, source_id,
       event_type, timestamp, descricao, ingested_at)
    VALUES (?, ?, ?, ?, ?, ?, 'recall_consulted', ?, ?, ?)
    ON CONFLICT(project, feature, wave, source_id) DO UPDATE SET
      event_type=excluded.event_type, descricao=excluded.descricao
  `);
  const ts = anchor.ingested_at ?? '2026-05-25T12:00:00Z';
  insEvent.run(anchor.project, anchor.feature, anchor.wave, anchor.execucao_id, ts, 'recall-consulted-001', ts, 'etapa=specify hits=3', ts);
  insEvent.run(anchor.project, anchor.feature, anchor.wave, anchor.execucao_id, ts, 'recall-consulted-002', ts, 'etapa=plan hits=0', ts);
  log('OK: 2 eventos recall_consulted (hits=3 produtiva, hits=0 vazia)');

  // 4. schema_version = 3
  db.prepare(`
    INSERT INTO schema_meta(key, value) VALUES('schema_version', '3')
    ON CONFLICT(key) DO UPDATE SET value=excluded.value
  `).run();

  const schemaVersion = db.prepare("SELECT value FROM schema_meta WHERE key='schema_version'").get().value;
  const recallConsulted = db.prepare("SELECT count(*) n FROM events WHERE event_type='recall_consulted'").get().n;
  return { schemaVersion, recallConsulted, titulos: updated.changes };
}

// ─── Runner standalone ────────────────────────────────────────────────────────
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const require = createRequire(import.meta.url);
  const TARGET_DB = resolve('apps/server/test/knowledge-fixture.db');

  if (!existsSync(TARGET_DB)) {
    console.error(`ERRO: fixture nao encontrada em ${TARGET_DB}`);
    process.exit(1);
  }
  let Database;
  try {
    Database = require('better-sqlite3');
  } catch {
    console.error('ERRO: better-sqlite3 nao encontrado. Execute npm install primeiro.');
    process.exit(1);
  }
  const db = new Database(TARGET_DB);
  try {
    const r = migrateFixtureToV3(db);
    console.log(`OK: schema_version='${r.schemaVersion}'; recall_consulted=${r.recallConsulted}`);
    console.log(`Fixture migrada para v3: ${TARGET_DB}`);
  } finally {
    db.close();
  }
}
