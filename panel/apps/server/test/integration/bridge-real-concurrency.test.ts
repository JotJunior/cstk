/**
 * Task 5.2.6 (docs/specs/human-bridge/tasks.md FASE 5, Cenario 7 do
 * quickstart) — Duas respostas simultaneas SOB CONCORRENCIA REAL, nao
 * simulada.
 *
 * `test/routes/bridge.test.ts` ja cobre a invariante de banco
 * (`FR-016/SC-006: duas respostas concorrentes — a primeira vence (200), a
 * segunda ve 409`) via `server.inject()` + `Promise.all`. Isso exercita a
 * clausula SQL (`UPDATE ... WHERE resolution IS NULL AND expires_at > ?`)
 * corretamente, mas `server.inject()` nunca abre socket TCP real — as duas
 * chamadas competem apenas pela ORDEM de agendamento de microtasks do MESMO
 * processo Node, nunca por uma corrida genuina de I/O de rede.
 *
 * Este teste sobe o servidor com `.listen()` (socket TCP real, loopback) e
 * dispara os DOIS `POST .../answer` via `fetch()` HTTP real e concorrente
 * (`Promise.all`), fechando a lacuna "nao simulada" do cenario.
 */
import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach } from 'vitest';
import Fastify from 'fastify';
import type { FastifyInstance } from 'fastify';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';
import { bridgeRoutes } from '../../src/routes/bridge.js';
import { resetSecretsFilterAvailabilityForTests } from '../../src/lib/secret-scrub.js';

let server: FastifyInstance;
let base: string;
let baseUrl: string;
const ORIGINAL_ENV = { ...process.env };

async function findFreePort(): Promise<number> {
  return await new Promise((resolve, reject) => {
    const srv = createServer();
    srv.on('error', reject);
    srv.listen(0, '127.0.0.1', () => {
      const addr = srv.address();
      if (addr && typeof addr === 'object') {
        const port = addr.port;
        srv.close(() => resolve(port));
      } else {
        srv.close(() => reject(new Error('porta livre indisponivel')));
      }
    });
  });
}

beforeAll(async () => {
  server = Fastify({ logger: false });
  await server.register(async (v1) => {
    await v1.register(bridgeRoutes);
  }, { prefix: '/api/v1' });
  const port = await findFreePort();
  await server.listen({ port, host: '127.0.0.1' });
  baseUrl = `http://127.0.0.1:${port}`;
});

afterAll(async () => {
  await server.close();
});

beforeEach(() => {
  base = mkdtempSync(join(tmpdir(), 'bridge-real-concurrency-'));
  process.env['CSTK_BRIDGE_DB'] = join(base, 'bridge.db');
  process.env['CSTK_SECRETS_FILTER'] = '/caminho/que/nao/existe/secrets-filter.sh';
  resetSecretsFilterAvailabilityForTests();
});

afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
  resetSecretsFilterAvailabilityForTests();
  rmSync(base, { recursive: true, force: true });
});

describe('5.2.6 Cenario 7 — duas respostas concorrentes SOB SOCKET TCP REAL (nao simulada)', () => {
  it('exatamente um 200 e um 409 sob fetch() HTTP real e concorrente contra o mesmo processo', async () => {
    const createRes = await fetch(`${baseUrl}/api/v1/bridge/interventions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        projectPath: '/tmp/proj-concorrencia',
        project: 'proj-concorrencia',
        shortName: null,
        executionKind: 'feature-00c',
        kind: 'choice',
        question: 'qual vence a corrida?',
        options: ['a', 'b'],
        defaultValue: 'a',
        timeoutMs: 240000,
      }),
    });
    expect(createRes.status).toBe(201);
    const created = (await createRes.json()) as { data: { questionId: string } };
    const { questionId } = created.data;

    const answerOnce = (value: string) =>
      fetch(`${baseUrl}/api/v1/bridge/interventions/${questionId}/answer`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ resolution: 'answered', value, text: null }),
      });

    // Concorrencia REAL: dois sockets TCP distintos, disparados juntos,
    // resolvidos em paralelo pelo event loop do MESMO processo servidor —
    // nao mais duas chamadas in-process de server.inject().
    const [first, second] = await Promise.all([answerOnce('a'), answerOnce('b')]);
    const statuses = [first.status, second.status].sort();
    expect(statuses).toEqual([200, 409]);

    // A sessao de origem recebe UM UNICO desfecho — confirmar que a fila
    // agora tem exatamente 1 resolucao (nao duas, nao zero).
    const pollRes = await fetch(`${baseUrl}/api/v1/bridge/interventions/${questionId}`);
    const polled = (await pollRes.json()) as { data: { state: string; appliedValue: string } };
    expect(polled.data.state).toBe('answered');
    expect(['a', 'b']).toContain(polled.data.appliedValue);
  });
});
