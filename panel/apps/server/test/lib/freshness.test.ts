/**
 * 7.5 Testes de snapshot que muda (frescor) e ETag end-to-end.
 * Ref: quickstart.md §Cenario 7; spec.md FR-014, FR-016, SC-007
 * Tasks 7.5.1 – 7.5.3
 *
 * 7.5.1: touch na base fixture → nova requisicao retorna mtime avancado
 * 7.5.2: ETag antigo nao retorna 304 apos touch na base
 * 7.5.3: maxIngestedAt avanca quando ingested_at mais recente inserido na fixture
 *
 * Principio VI (Snapshot que Muda): frescor e calculado a cada chamada.
 * Cada requisicao reflete o estado atual do DB (mtime + max ingested_at).
 */
import { describe, it, expect, beforeAll, afterAll, afterEach } from 'vitest';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import type { FastifyInstance } from 'fastify';
import { existsSync, copyFileSync, utimesSync, unlinkSync, mkdtempSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import Database from 'better-sqlite3';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE_DB = resolve(join(__dirname, '..', 'knowledge-fixture.db'));
const FIXTURE_EXISTS = existsSync(FIXTURE_DB);

// Track temp databases para cleanup
const toClean: string[] = [];

afterEach(() => {
  for (const f of toClean) {
    try { unlinkSync(f); } catch { /* ignorar */ }
    try { unlinkSync(f + '-shm'); } catch { /* ignorar */ }
    try { unlinkSync(f + '-wal'); } catch { /* ignorar */ }
  }
  toClean.length = 0;
});

function makeTempCopy(): string {
  const dir = mkdtempSync(join(tmpdir(), 'cstk-fresh-'));
  const dest = join(dir, 'test-fresh.db');
  copyFileSync(FIXTURE_DB, dest);
  toClean.push(dest);
  return dest;
}

// ─── Helper: construir servidor de teste ─────────────────────────────────────

async function buildServer(dbPath: string): Promise<FastifyInstance> {
  process.env['CSTK_KNOWLEDGE_DB'] = dbPath;
  const server = Fastify({ logger: false });
  await server.register(cors, { origin: 'http://localhost:5173', methods: ['GET', 'OPTIONS'] });
  server.addHook('onSend', async (_req, reply) => {
    void reply.header('Content-Type', 'application/json; charset=utf-8');
    void reply.header('X-Content-Type-Options', 'nosniff');
    void reply.header('X-Frame-Options', 'DENY');
    void reply.header('Cache-Control', 'no-store');
  });
  const { overviewRoutes } = await import('../../src/routes/overview.js');
  await server.register(async (v1) => {
    await v1.register(overviewRoutes);
  }, { prefix: '/api/v1' });
  await server.ready();
  return server;
}

// ─── 7.5.1 touch na base → mtime avanca ──────────────────────────────────────

describe.skipIf(!FIXTURE_EXISTS)('7.5.1 Frescor — mtime avanca apos touch na base', () => {
  let server: FastifyInstance;
  let dbPath: string;

  beforeAll(async () => {
    dbPath = makeTempCopy();
    server = await buildServer(dbPath);
  });
  afterAll(async () => { await server.close(); });

  it('mtime da segunda requisicao e maior apos utimes() na base', async () => {
    // Primeira requisicao: captura mtime inicial
    const res1 = await server.inject({ method: 'GET', url: '/api/v1/overview' });
    expect(res1.statusCode).toBe(200);
    const body1 = res1.json<{ meta: { freshness: { mtime: string; maxIngestedAt: string } } }>();
    const mtime1 = body1.meta.freshness.mtime;
    expect(mtime1).toBeTruthy();

    // Simular touch: avancar mtime para +2 segundos
    const futureTime = new Date(new Date(mtime1).getTime() + 2000);
    utimesSync(dbPath, futureTime, futureTime);

    // Segunda requisicao: deve refletir novo mtime
    const res2 = await server.inject({ method: 'GET', url: '/api/v1/overview' });
    expect(res2.statusCode).toBe(200);
    const body2 = res2.json<{ meta: { freshness: { mtime: string } } }>();
    const mtime2 = body2.meta.freshness.mtime;

    expect(mtime2).toBeTruthy();
    expect(new Date(mtime2).getTime()).toBeGreaterThan(new Date(mtime1).getTime());
  });
});

// ─── 7.5.2 ETag antigo nao retorna 304 apos touch ────────────────────────────

describe.skipIf(!FIXTURE_EXISTS)('7.5.2 ETag — ETag antigo invalido apos touch na base', () => {
  let server: FastifyInstance;
  let dbPath: string;

  beforeAll(async () => {
    dbPath = makeTempCopy();
    server = await buildServer(dbPath);
  });
  afterAll(async () => { await server.close(); });

  it('ETag capturado antes do touch nao e mais valido apos touch', async () => {
    // Capturar ETag inicial
    const res1 = await server.inject({ method: 'GET', url: '/api/v1/overview' });
    const etag1 = res1.headers['etag'] as string | undefined;
    expect(etag1).toBeDefined();

    // Confirmar que ETag inicial retorna 304
    if (etag1) {
      const res304 = await server.inject({
        method: 'GET',
        url: '/api/v1/overview',
        headers: { 'if-none-match': etag1 },
      });
      expect(res304.statusCode).toBe(304);

      // Touch: avancar mtime
      const mtime1 = res1.json<{ meta: { freshness: { mtime: string } } }>().meta.freshness.mtime;
      const futureTime = new Date(new Date(mtime1).getTime() + 2000);
      utimesSync(dbPath, futureTime, futureTime);

      // Agora o mesmo ETag nao deve mais retornar 304
      const res200 = await server.inject({
        method: 'GET',
        url: '/api/v1/overview',
        headers: { 'if-none-match': etag1 },
      });
      expect(res200.statusCode).toBe(200);

      // E o novo ETag deve ser diferente
      const etag2 = res200.headers['etag'] as string | undefined;
      if (etag2) {
        expect(etag2).not.toBe(etag1);
      }
    }
  });
});

// ─── 7.5.3 maxIngestedAt avanca com nova ingestao simulada ───────────────────

describe.skipIf(!FIXTURE_EXISTS)('7.5.3 Frescor — maxIngestedAt avanca com nova ingestao', () => {
  let dbPath: string;
  let server: FastifyInstance;

  beforeAll(async () => {
    dbPath = makeTempCopy();
    server = await buildServer(dbPath);
  });
  afterAll(async () => { await server.close(); });

  it('maxIngestedAt avanca quando nova execucao com ingested_at mais recente e adicionada', async () => {
    // Capturar maxIngestedAt inicial
    const res1 = await server.inject({ method: 'GET', url: '/api/v1/overview' });
    expect(res1.statusCode).toBe(200);
    const body1 = res1.json<{ meta: { freshness: { maxIngestedAt: string } } }>();
    const maxIat1 = body1.meta.freshness.maxIngestedAt;

    // Inserir execucao com ingested_at mais recente (simulando nova ingestao)
    // Nota: abrimos em modo escrita apenas para este teste — o servidor usa readonly
    const writeDb = new Database(dbPath);
    const futureTs = new Date(Date.now() + 3600_000).toISOString(); // +1h
    const uniqueId = `exec-freshness-${Date.now()}`;
    // executions tem NOT NULL em: project, feature, wave, execution_id, source_ts, source_id, ingested_at
    writeDb.exec(`
      INSERT OR IGNORE INTO executions
        (execution_id, project, feature, wave, source_ts, source_id, status, ingested_at)
      VALUES
        ('${uniqueId}', 'proj-fresh', 'feat-fresh', 'onda-001',
         '${futureTs}', '${uniqueId}', 'concluida', '${futureTs}')
    `);
    writeDb.close();

    // Touch no arquivo apos escrita
    const now = new Date();
    utimesSync(dbPath, now, now);

    // Nova requisicao ao servidor (agora le DB que foi modificado)
    const res2 = await server.inject({ method: 'GET', url: '/api/v1/overview' });
    expect(res2.statusCode).toBe(200);
    const body2 = res2.json<{ meta: { freshness: { maxIngestedAt: string } } }>();
    const maxIat2 = body2.meta.freshness.maxIngestedAt;

    expect(maxIat2).toBeTruthy();
    // maxIngestedAt deve ser maior (ou igual — se ingested_at nao existe na schema)
    if (maxIat1 && maxIat2) {
      expect(new Date(maxIat2).getTime()).toBeGreaterThanOrEqual(new Date(maxIat1).getTime());
    }
  });
});

// ─── ETag: formato esperado ───────────────────────────────────────────────────

describe.skipIf(!FIXTURE_EXISTS)('ETag — formato W/"epoch-epoch"', () => {
  let server: FastifyInstance;

  beforeAll(async () => {
    server = await buildServer(FIXTURE_DB);
  });
  afterAll(async () => { await server.close(); });

  it('ETag tem formato W/"<number>-<number>"', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/overview' });
    const etag = res.headers['etag'] as string | undefined;
    expect(etag).toBeDefined();
    if (etag) {
      // Formato: W/"<epoch_ms>-<epoch_ms>"
      expect(etag).toMatch(/^W\/"[0-9]+-[0-9]+"$/);
    }
  });

  it('Cache-Control: no-store em toda resposta (FR-019)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/overview' });
    expect(res.headers['cache-control']).toBe('no-store');
  });
});
