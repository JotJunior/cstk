/**
 * Task 5.2.7 (docs/specs/human-bridge/tasks.md FASE 5, Cenario 8 do
 * quickstart) — Degradacao ISOLADA do `bridge.db` (FR-017, Principio II).
 *
 * `bridge.db` (conexao read-write dedicada, `db/bridge.ts`) e `knowledge.db`
 * (conexao readonly do corpus, `db/open.ts`) sao arquivos SEPARADOS abertos
 * por codigo SEPARADO — mas essa separacao nunca tinha sido provada com os
 * DOIS conjuntos de rotas registrados JUNTOS no MESMO servidor Fastify e
 * exercitados na MESMA requisicao de teste. `test/routes/bridge.test.ts`
 * (isolado) e `test/lib/server-health.test.ts` (rota `/health` MOCADA, sem
 * `openDb` real) nunca colocam as duas coisas lado a lado.
 *
 * Este teste registra `healthRoutes` (rota REAL, usa `db/open.ts`/
 * `openDb`) + `bridgeRoutes` (rota REAL, usa `db/bridge.ts`/`openBridgeDb`)
 * no MESMO servidor, quebra `bridge.db` (diretorio bloqueado por um
 * arquivo regular no lugar — mesmo truque de `test/routes/bridge.test.ts`)
 * e confirma que:
 *   1. `GET /api/v1/bridge/interventions` degrada (200 + meta.degraded=true,
 *      reason `bridge_unavailable`) — o esperado quando bridge.db quebra;
 *   2. `GET /api/v1/health` continua 200, e seu `meta.reason` (quando
 *      degradado) e SEMPRE `db-missing` (o motivo do KNOWLEDGE.DB, nao
 *      relacionado a Ponte) — NUNCA `bridge_unavailable` nem qualquer razao
 *      cruzada — provando que a queda da Ponte nao vaza para a tela de
 *      observabilidade;
 *   3. o inverso tambem vale: com `bridge.db` SAUDAVEL restaurado, a fila
 *      da Ponte volta a `degraded:false` sem precisar reiniciar o processo
 *      (mesma conexao aberta sob demanda a cada request, nunca cacheada).
 */
import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach } from 'vitest';
import Fastify from 'fastify';
import type { FastifyInstance } from 'fastify';
import { mkdtempSync, rmSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { healthRoutes } from '../../src/routes/health.js';
import { bridgeRoutes } from '../../src/routes/bridge.js';

let server: FastifyInstance;
let base: string;
const ORIGINAL_ENV = { ...process.env };
const VALID_HOST = { host: '127.0.0.1' };

// IMPORTANTE: `healthRoutes(server)` chama `loadConfig()` (portanto le
// `CSTK_KNOWLEDGE_DB`) UMA UNICA VEZ no REGISTRO da rota (dentro de
// `beforeAll`) — ao contrario de `bridgeRoutes`, que resolve
// `CSTK_BRIDGE_DB` a cada request via `openBridgeDb()`/`resolveBridgeDbPath()`
// dentro do handler. Por isso o path de knowledge.db PRECISA estar fixado
// ANTES do `server.register` rodar — mudar `CSTK_KNOWLEDGE_DB` em
// `beforeEach` (DEPOIS do registro) nao tem efeito nenhum sobre `/health`
// (ficaria lendo o `knowledge.db` REAL da maquina do operador, se existir,
// mascarando a asercao). `CSTK_BRIDGE_DB` continua podendo variar por teste
// livremente.
const FIXED_MISSING_KNOWLEDGE_DB = join(
  mkdtempSync(join(tmpdir(), 'bridge-degradation-fixedcfg-')),
  'knowledge-inexistente.db',
);
process.env['CSTK_KNOWLEDGE_DB'] = FIXED_MISSING_KNOWLEDGE_DB;

beforeAll(async () => {
  server = Fastify({ logger: false });
  await server.register(async (v1) => {
    await v1.register(healthRoutes);
    await v1.register(bridgeRoutes);
  }, { prefix: '/api/v1' });
  await server.ready();
});

afterAll(async () => {
  await server.close();
});

beforeEach(() => {
  base = mkdtempSync(join(tmpdir(), 'bridge-degradation-isolation-'));
});

afterEach(() => {
  process.env = { ...ORIGINAL_ENV, CSTK_KNOWLEDGE_DB: FIXED_MISSING_KNOWLEDGE_DB };
  rmSync(base, { recursive: true, force: true });
});

describe('5.2.7 Cenario 8 — degradacao isolada do bridge.db (FR-017/Principio II)', () => {
  it('bridge.db quebrado: /bridge/interventions degrada, /health NAO herda a razao da Ponte', async () => {
    // Mesmo truque de test/routes/bridge.test.ts: um arquivo regular no
    // lugar de um diretorio pai impede `mkdirSync(dir, {recursive:true})`
    // dentro de openBridgeDb() — bridge.db fica genuinamente inalcancavel.
    const blockerFile = join(base, 'bloqueado');
    writeFileSync(blockerFile, 'x');
    process.env['CSTK_BRIDGE_DB'] = join(base, 'bloqueado', 'nested', 'bridge.db');

    const bridgeRes = await server.inject({
      method: 'GET',
      url: '/api/v1/bridge/interventions',
      headers: VALID_HOST,
    });
    expect(bridgeRes.statusCode).toBe(200);
    const bridgeBody = bridgeRes.json() as { meta: { degraded: boolean; reason: string | null } };
    expect(bridgeBody.meta.degraded).toBe(true);
    expect(bridgeBody.meta.reason).toBe('bridge_unavailable');

    const healthRes = await server.inject({ method: 'GET', url: '/api/v1/health' });
    expect(healthRes.statusCode).toBe(200);
    const healthBody = healthRes.json() as { meta: { degraded: boolean; reason: string | null } };
    // knowledge.db esta ausente por CONSTRUCAO desta suite — degrada, mas
    // por um motivo TOTALMENTE alheio ao estado de bridge.db.
    expect(healthBody.meta.degraded).toBe(true);
    expect(healthBody.meta.reason).toBe('db-missing');
    expect(healthBody.meta.reason).not.toBe('bridge_unavailable');
  });

  it('bridge.db restaurado (saudavel): a fila volta a degraded:false SEM reiniciar o processo', async () => {
    // 1) Quebrado primeiro.
    const blockerFile = join(base, 'bloqueado2');
    writeFileSync(blockerFile, 'x');
    process.env['CSTK_BRIDGE_DB'] = join(base, 'bloqueado2', 'nested', 'bridge.db');
    const degradedRes = await server.inject({
      method: 'GET',
      url: '/api/v1/bridge/interventions',
      headers: VALID_HOST,
    });
    expect((degradedRes.json() as { meta: { degraded: boolean } }).meta.degraded).toBe(true);

    // 2) Restaurado: path saudavel, sem reiniciar `server` (mesma
    // instancia Fastify, mesma conexao aberta SOB DEMANDA por request —
    // openBridgeDb() e chamado dentro do handler, nunca cacheado no boot).
    const healthyDir = mkdtempSync(join(tmpdir(), 'bridge-healthy-'));
    process.env['CSTK_BRIDGE_DB'] = join(healthyDir, 'bridge.db');
    try {
      const restoredRes = await server.inject({
        method: 'GET',
        url: '/api/v1/bridge/interventions',
        headers: VALID_HOST,
      });
      expect(restoredRes.statusCode).toBe(200);
      const restoredBody = restoredRes.json() as { meta: { degraded: boolean } };
      expect(restoredBody.meta.degraded).toBe(false);
    } finally {
      rmSync(healthyDir, { recursive: true, force: true });
    }
  });

  it('resposta de /health e BYTE-A-BYTE identica antes/depois de bridge.db quebrar (zero cross-contamination)', async () => {
    const before = await server.inject({ method: 'GET', url: '/api/v1/health' });
    expect(before.statusCode).toBe(200);

    const blockerFile = join(base, 'bloqueado3');
    writeFileSync(blockerFile, 'x');
    process.env['CSTK_BRIDGE_DB'] = join(base, 'bloqueado3', 'nested', 'bridge.db');
    // Confirma que a quebra de fato se manifesta na Ponte nesta mesma janela.
    const bridgeRes = await server.inject({
      method: 'GET',
      url: '/api/v1/bridge/interventions',
      headers: VALID_HOST,
    });
    expect((bridgeRes.json() as { meta: { degraded: boolean } }).meta.degraded).toBe(true);

    const after = await server.inject({ method: 'GET', url: '/api/v1/health' });
    expect(after.statusCode).toBe(200);
    // `data.path`/timestamps de health nao mudam entre as duas chamadas
    // (config resolvida uma vez no boot) — a resposta inteira deve bater.
    expect(after.json()).toEqual(before.json());
  });
});
