/**
 * Script para criar knowledge-fixture.db para testes de integracao.
 * Executa APOS npm install (requer better-sqlite3).
 *
 * Uso: node scripts/create-fixture.mjs
 */
import { copyFileSync, existsSync, rmSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { createRequire } from 'node:module';
import { migrateFixtureToV3 } from './migrate-fixture-v3.mjs';

const require = createRequire(import.meta.url);

const DEFAULT_DB = join(homedir(), '.claude', 'cstk', 'knowledge.db');
const SOURCE_DB = process.env['CSTK_KNOWLEDGE_DB'] || DEFAULT_DB;
const TARGET_DB = resolve('apps/server/test/knowledge-fixture.db');

if (!existsSync(SOURCE_DB)) {
  console.error(`ERRO: knowledge.db nao encontrada em ${SOURCE_DB}`);
  console.error('Defina CSTK_KNOWLEDGE_DB para apontar para a base correta.');
  process.exit(1);
}

console.log(`Copiando ${SOURCE_DB} → ${TARGET_DB} ...`);
// Remover sidecars -wal/-shm de uma fixture anterior ANTES da copia: senao o
// SQLite recupera paginas obsoletas no .db recem-copiado (estado inconsistente).
for (const sfx of ['-wal', '-shm']) {
  try { rmSync(TARGET_DB + sfx); } catch { /* inexistente — ok */ }
}
copyFileSync(SOURCE_DB, TARGET_DB);

// Verificar schema aceito (read-only)
let Database;
try {
  Database = require('better-sqlite3');
} catch {
  console.error('ERRO: better-sqlite3 nao encontrado. Execute npm install primeiro.');
  process.exit(1);
}

// Migrar a fixture para v3 (read-write) — deterministico, independente da versao
// da base de origem. Garante que a fixture de integracao SEMPRE exercite o schema
// corrente (titulo + recall_consulted) e que os testes sejam reprodutiveis.
const dbRW = new Database(TARGET_DB, { fileMustExist: true });
try {
  const r = migrateFixtureToV3(dbRW);
  console.log(`OK: fixture migrada para schema v${r.schemaVersion} (recall_consulted=${r.recallConsulted})`);
} finally {
  dbRW.close();
}

// Verificacao final (read-only) — esperado v3
const db = new Database(TARGET_DB, { readonly: true, fileMustExist: true });
try {
  const row = db.prepare(
    "SELECT value FROM schema_meta WHERE key = 'schema_version'"
  ).get();

  if (!row || row.value !== '3') {
    console.error(`ERRO: schema_version esperado '3' apos migracao, encontrado: ${row?.value ?? 'nenhum'}`);
    process.exit(1);
  }

  const counts = db.prepare(`
    SELECT
      (SELECT count(*) FROM executions) as execucoes,
      (SELECT count(*) FROM waves) as ondas,
      (SELECT count(*) FROM decisions) as decisoes
  `).get();

  console.log(`OK: schema v${row.value} confirmado`);
  console.log(`   Execucoes: ${counts.execucoes}`);
  console.log(`   Ondas:     ${counts.ondas}`);
  console.log(`   Decisoes:  ${counts.decisoes}`);
  console.log(`Fixture criada em: ${TARGET_DB}`);
} finally {
  db.close();
}
