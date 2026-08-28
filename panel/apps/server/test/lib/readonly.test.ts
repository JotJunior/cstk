/**
 * 7.3 Testes de seguranca e read-only.
 * Ref: quickstart.md §Cenario 5 e §Cenario 8; spec.md SC-003, SC-005
 * Tasks 7.3.1 – 7.3.4
 *
 * 7.3.1: grep -rniE em apps/server/src — 0 verbos de mutacao (SC-003)
 * 7.3.2: abertura com readonly: true + PRAGMA query_only (inspecionar open.ts)
 * 7.3.3: payloads FTS5 hostis — todos retornam 200, nunca 5xx
 * 7.3.4: payload de tamanho maximo excedido → 400 sem stack trace
 *
 * Constitution Principio I: Read-Only Absoluto.
 */
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import type { FastifyInstance } from 'fastify';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE_DB = resolve(join(__dirname, '..', 'knowledge-fixture.db'));
const FIXTURE_EXISTS = existsSync(FIXTURE_DB);

// Path do codigo fonte do servidor (para inspecao grep)
const SERVER_SRC = resolve(join(__dirname, '..', '..', 'src'));

// ─── 7.3.1 Grep de verbos de mutacao em apps/server/src ─────────────────────

/**
 * Coleta todos os arquivos .ts recursivamente sob um diretorio.
 */
function collectTsFiles(dir: string): string[] {
  const files: string[] = [];
  try {
    for (const entry of readdirSync(dir)) {
      const full = join(dir, entry);
      const stat = statSync(full);
      if (stat.isDirectory()) {
        files.push(...collectTsFiles(full));
      } else if (entry.endsWith('.ts')) {
        files.push(full);
      }
    }
  } catch { /* ignorar erros de IO */ }
  return files;
}

/**
 * Verifica se algum arquivo contem padroes de mutacao SQL.
 * Retorna lista de matches: { file, line, content }.
 */
function findMutationPatterns(srcDir: string): { file: string; line: number; content: string }[] {
  // Padroes SQL de mutacao (SC-003)
  const MUTATION_PATTERNS = [
    /\bINSERT\s+INTO\b/i,
    /\bUPDATE\s+\w/i,
    /\bDELETE\s+FROM\b/i,
    /\bDROP\s+TABLE\b/i,
    /\bCREATE\s+TABLE\b/i,
    /\bALTER\s+TABLE\b/i,
    /\.exec\s*\(\s*['"`].*(?:INSERT|UPDATE|DELETE|DROP|CREATE|ALTER)/i,
    /\.prepare\s*\(\s*['"`].*(?:INSERT|UPDATE|DELETE|DROP|CREATE|ALTER)/i,
  ];

  // Padroes que DEVEM ser excluidos (sao do codigo de abertura/pragma — nao mutacao de dados)
  const SAFE_PATTERNS = [
    /PRAGMA\s+query_only/i,
    /PRAGMA\s+quick_check/i,
    /CREATE\s+TABLE\s+schema_meta/i,  // nao esperado em src
  ];

  const matches: { file: string; line: number; content: string }[] = [];
  const files = collectTsFiles(srcDir);

  for (const file of files) {
    // Excluir arquivos de teste
    if (file.includes('/test/') || file.includes('.test.ts')) continue;

    let content: string;
    try {
      content = readFileSync(file, 'utf8');
    } catch {
      continue;
    }

    const lines = content.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]!;

      // Pular comentarios
      const trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('*') || trimmed.startsWith('/*')) continue;

      for (const pattern of MUTATION_PATTERNS) {
        if (pattern.test(line)) {
          // Verificar se e um padrao seguro conhecido
          const isSafe = SAFE_PATTERNS.some((safe) => safe.test(line));
          if (!isSafe) {
            matches.push({ file: file.replace(SERVER_SRC, 'src'), line: i + 1, content: trimmed.slice(0, 100) });
          }
          break;
        }
      }
    }
  }

  return matches;
}

describe('7.3.1 Read-Only Absoluto — grep de verbos de mutacao em src/', () => {
  it('nao ha verbos de mutacao SQL em apps/server/src (SC-003)', () => {
    const matches = findMutationPatterns(SERVER_SRC);
    expect(
      matches,
      `Verbos de mutacao encontrados:\n${matches.map((m) => `  ${m.file}:${m.line}: ${m.content}`).join('\n')}`
    ).toHaveLength(0);
  });

  it('nao ha endpoint nao-GET registrado (router.post/put/patch/delete ausentes)', () => {
    const NON_GET_PATTERNS = [
      /\bserver\.(post|put|patch|delete)\b/i,
      /\bscoped\.(post|put|patch|delete)\b/i,
      /\bfastify\.(post|put|patch|delete)\b/i,
    ];

    const files = collectTsFiles(SERVER_SRC);
    const matches: { file: string; line: number; content: string }[] = [];

    for (const file of files) {
      if (file.includes('/test/') || file.includes('.test.ts')) continue;
      let content: string;
      try { content = readFileSync(file, 'utf8'); } catch { continue; }

      const lines = content.split('\n');
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i]!;
        const trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
        for (const pattern of NON_GET_PATTERNS) {
          if (pattern.test(line)) {
            matches.push({ file: file.replace(SERVER_SRC, 'src'), line: i + 1, content: trimmed.slice(0, 100) });
            break;
          }
        }
      }
    }

    expect(
      matches,
      `Endpoints nao-GET encontrados:\n${matches.map((m) => `  ${m.file}:${m.line}: ${m.content}`).join('\n')}`
    ).toHaveLength(0);
  });
});

// ─── 7.3.2 open.ts: readonly: true + PRAGMA query_only ───────────────────────

describe('7.3.2 open.ts — leitura de readonly e PRAGMA query_only', () => {
  it('open.ts contem readonly: true na abertura do banco', () => {
    const openTs = readFileSync(resolve(join(SERVER_SRC, 'db', 'open.ts')), 'utf8');
    expect(openTs).toMatch(/readonly\s*:\s*true/);
  });

  it('open.ts contem PRAGMA query_only = 1', () => {
    const openTs = readFileSync(resolve(join(SERVER_SRC, 'db', 'open.ts')), 'utf8');
    expect(openTs).toMatch(/query_only\s*=\s*1/);
  });
});

// ─── 7.3.3 Payloads FTS5 hostis — 200 nunca 5xx ──────────────────────────────

describe.skipIf(!FIXTURE_EXISTS)('7.3.3 FTS5 payloads hostis — nunca 5xx', () => {
  let server: FastifyInstance;

  beforeAll(async () => {
    process.env['CSTK_KNOWLEDGE_DB'] = FIXTURE_DB;
    const s = Fastify({ logger: false });
    await s.register(cors, { origin: 'http://localhost:5173', methods: ['GET', 'OPTIONS'] });
    s.addHook('onSend', async (_req, reply) => {
      void reply.header('Content-Type', 'application/json; charset=utf-8');
      void reply.header('X-Content-Type-Options', 'nosniff');
      void reply.header('X-Frame-Options', 'DENY');
      void reply.header('Cache-Control', 'no-store');
    });
    const { searchRoutes } = await import('../../src/routes/search.js');
    await s.register(async (v1) => {
      await v1.register(searchRoutes);
    }, { prefix: '/api/v1' });
    await s.ready();
    server = s;
  });
  afterAll(async () => { await server.close(); });

  // Payloads hostis do quickstart.md §Cenario 8
  const HOSTILE_QUERIES = [
    { q: '") OR 1=1 --', label: 'SQL injection classico' },
    { q: "'single", label: 'aspas simples' },
    { q: 'NEAR/3(a b)', label: 'FTS5 NEAR operator' },
    { q: '; DROP TABLE decisions; --', label: 'DROP TABLE injection' },
    { q: '")) OR ((1))=(1) --', label: 'boolean injection' },
    { q: '"unclosed', label: 'aspas duplas nao fechadas' },
    { q: 'SELECT * FROM executions', label: 'SELECT injection' },
    { q: 'MATCH knowledge_fts', label: 'MATCH keyword' },
    { q: '\x00\x01\x02null bytes', label: 'bytes nulos' },
    { q: '<script>alert(1)</script>', label: 'XSS payload' },
  ];

  for (const { q, label } of HOSTILE_QUERIES) {
    it(`retorna 200 (nao 5xx) para: ${label}`, async () => {
      const res = await server.inject({
        method: 'GET',
        url: `/api/v1/search?q=${encodeURIComponent(q)}`,
      });
      expect(res.statusCode, `5xx para query hostil: ${label}`).toBe(200);
    });
  }
});

// ─── 7.3.4 Payload de tamanho maximo → 400 sem stack trace ───────────────────

describe('7.3.4 Limite de tamanho em /search → 400 sem stack trace', () => {
  let server: FastifyInstance;

  beforeAll(async () => {
    // Usar path degradado — limite de tamanho e validado antes do DB
    process.env['CSTK_KNOWLEDGE_DB'] = '/tmp/cstk-size-test-' + Date.now() + '.db';
    const s = Fastify({ logger: false });
    await s.register(cors, { origin: 'http://localhost:5173', methods: ['GET', 'OPTIONS'] });
    s.addHook('onSend', async (_req, reply) => {
      void reply.header('Content-Type', 'application/json; charset=utf-8');
    });
    const { searchRoutes } = await import('../../src/routes/search.js');
    await s.register(async (v1) => {
      await v1.register(searchRoutes);
    }, { prefix: '/api/v1' });
    await s.ready();
    server = s;
  });
  afterAll(async () => { await server.close(); });

  it('q com mais de 200 chars retorna 400', async () => {
    const longQ = 'a'.repeat(201);
    const res = await server.inject({ method: 'GET', url: `/api/v1/search?q=${longQ}` });
    expect(res.statusCode).toBe(400);
  });

  it('resposta 400 nao contem stack trace (sem "Error:" nem " at ")', async () => {
    const longQ = 'a'.repeat(201);
    const res = await server.inject({ method: 'GET', url: `/api/v1/search?q=${longQ}` });
    const body = res.json<{ error?: string }>();
    const errorStr = typeof body.error === 'string' ? body.error : '';
    expect(errorStr).not.toMatch(/Error:/);
    expect(errorStr).not.toMatch(/\s+at\s+\w/);
    // Deve ter mensagem descritiva
    expect(body.error).toBeDefined();
  });

  it('q vazio retorna 400', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/search?q=' });
    expect(res.statusCode).toBe(400);
  });
});
