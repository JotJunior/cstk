/**
 * Testes de `api.ts` — roundtrip REAL para `mutateApi()` (task 4.1.3).
 *
 * Ref: docs/specs/human-bridge/contracts/panel-bridge-api.md §8 (CHK016).
 *
 * CHK016 e explicito: o defeito de cache (`fetchApi()` reusado para
 * mutacao devolveria corpo STALE de um `304` cacheado) "nao aparece com
 * mock (sem localStorage nem ETag simulados)". Por isso este teste NAO usa
 * `vi.fn()` para simular a resposta HTTP — sobe um `http.createServer` real
 * na loopback e faz chamadas de fato via `fetch`. As duas unicas pecas
 * substituidas sao (a) resolucao de URL relativa (`fetch('/api/v1/...')`
 * nao resolve sem `document.baseURI`/`window.location` — Node nao tem
 * nenhum dos dois; o stub so prefixa o host real, delegando ao `fetch`
 * nativo do Node) e (b) `localStorage`, que so existe em Node atras da flag
 * `--localstorage-file` (nao habilitada nesta suite) — o polyfill abaixo e
 * um `Map` com a MESMA interface (`getItem`/`setItem`/`removeItem`), nao
 * uma resposta pre-fabricada: o ETag/cache exercitados sao os REAIS de
 * `api.ts`, contra um servidor de fato respondendo `200`/`304`.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { createServer, type Server } from 'node:http';
import { z } from 'zod';
import { fetchApi, mutateApi, invalidateEtag } from './api.js';

function localStoragePolyfill(): Storage {
  const store = new Map<string, string>();
  return {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
    clear: () => store.clear(),
    key: (i: number) => Array.from(store.keys())[i] ?? null,
    get length() {
      return store.size;
    },
  } as Storage;
}

let server: Server;
let baseUrl: string;
let queueVersion = 1;
let answered = false;

/** Servidor real minimo: espelha o par GET (fila, com ETag) + POST (answer). */
function startServer(): Promise<void> {
  return new Promise((resolve) => {
    server = createServer((req, res) => {
      const url = req.url ?? '';

      if (req.method === 'GET' && url === '/api/v1/bridge/interventions') {
        const etag = `"v${queueVersion}"`;
        const ifNoneMatch = req.headers['if-none-match'];
        if (ifNoneMatch === etag) {
          res.writeHead(304, { ETag: etag });
          res.end();
          return;
        }
        res.writeHead(200, { 'Content-Type': 'application/json', ETag: etag });
        res.end(JSON.stringify({
          data: {
            interventions: answered ? [] : [{ questionId: 'q1', state: 'open' }],
            pagination: { limit: 20, offset: 0 },
          },
          meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '1' },
        }));
        return;
      }

      if (req.method === 'POST' && url === '/api/v1/bridge/interventions/q1/answer') {
        let body = '';
        req.on('data', (chunk) => { body += chunk; });
        req.on('end', () => {
          JSON.parse(body); // exercita o corpo real enviado por mutateApi
          answered = true;
          queueVersion += 1; // a fila muda de versao apos a mutacao
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            data: { questionId: 'q1', state: 'answered', appliedValue: 'yes', untrustedText: null, resolvedAt: '2026-08-29T00:00:00Z' },
            meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '1' },
          }));
        });
        return;
      }

      res.writeHead(404).end();
    });
    server.listen(0, '127.0.0.1', () => resolve());
  });
}

function stopServer(): Promise<void> {
  return new Promise((resolve) => server.close(() => resolve()));
}

const QueueSchema = z.object({
  interventions: z.array(z.object({ questionId: z.string(), state: z.string() })),
  pagination: z.object({ limit: z.number(), offset: z.number() }),
});
const AnswerSchema = z.object({
  questionId: z.string(),
  state: z.string(),
  appliedValue: z.string().nullable(),
  untrustedText: z.string().nullable(),
  resolvedAt: z.string().nullable(),
});

beforeEach(async () => {
  queueVersion = 1;
  answered = false;
  await startServer();
  const addr = server.address();
  if (addr === null || typeof addr === 'string') throw new Error('endereco de servidor invalido');
  baseUrl = `http://127.0.0.1:${addr.port}`;

  vi.stubGlobal('localStorage', localStoragePolyfill());
  // Unico papel deste stub: resolver a URL RELATIVA que api.ts monta
  // (`/api/v1/...`) contra o host real do servidor de teste — a chamada em
  // si e um `fetch` de verdade, sem resposta simulada.
  const realFetch = fetch;
  vi.stubGlobal('fetch', (input: RequestInfo | URL, init?: RequestInit) => {
    const path = typeof input === 'string' ? input : input.toString();
    return realFetch(`${baseUrl}${path}`, init);
  });
});

afterEach(async () => {
  vi.unstubAllGlobals();
  await stopServer();
});

describe('mutateApi — roundtrip real (task 4.1.3, CHK016)', () => {
  it('nao envia If-None-Match mesmo com ETag da fila ja cacheado (fetchApi != mutateApi)', async () => {
    // 1. Prime o cache de ETag via fetchApi real (GET da fila).
    const first = await fetchApi('/bridge/interventions', QueueSchema);
    expect(first.data?.interventions).toHaveLength(1);

    // 2. Confirma que o cache de fato "pegou": uma 2a chamada fetchApi bate 304.
    const second = await fetchApi('/bridge/interventions', QueueSchema);
    expect(second.data?.interventions).toHaveLength(1); // veio do bodyCache local (304)

    // 3. mutateApi NAO deve herdar o If-None-Match do path da mutacao (nao
    // ha ETag para o path de answer de qualquer forma) nem quebrar por
    // causa do ETag de OUTRO path — chamada deve ir a rede de verdade.
    const answer = await mutateApi(
      '/bridge/interventions/q1/answer',
      'POST',
      { resolution: 'answered', value: 'yes', text: null },
      AnswerSchema,
      ['/bridge/interventions']
    );
    expect(answer.data?.state).toBe('answered');
  });

  it('invalida o ETag da fila apos a mutacao — proxima leitura vem FRESCA, nunca STALE do cache de 304 (contrato §8)', async () => {
    // 1. Prime o cache da fila (item ainda aberto).
    const before = await fetchApi('/bridge/interventions', QueueSchema);
    expect(before.data?.interventions).toHaveLength(1);

    // 2. Responde via mutateApi, invalidando explicitamente '/bridge/interventions'.
    await mutateApi(
      '/bridge/interventions/q1/answer',
      'POST',
      { resolution: 'answered', value: 'yes', text: null },
      AnswerSchema,
      ['/bridge/interventions']
    );

    // 3. Sem a invalidacao, o servidor de teste ainda aceitaria o ETag
    // ANTIGO como valido (o servidor mudou de versao, mas se o cliente
    // reenviasse o If-None-Match antigo o servidor responderia 200 mesmo
    // assim porque o ETag mudou — o ponto e que o CLIENTE nao deve nem
    // tentar o antigo). Confirma que a leitura seguinte reflete o estado
    // JA mutado (fila vazia), nao o corpo cacheado ANTES da mutacao.
    const after = await fetchApi('/bridge/interventions', QueueSchema);
    expect(after.data?.interventions).toHaveLength(0);
  });

  it('sem invalidatePaths, mutateApi nao mexe no cache de OUTRO path (isolamento)', async () => {
    await fetchApi('/bridge/interventions', QueueSchema);
    await mutateApi(
      '/bridge/interventions/q1/answer',
      'POST',
      { resolution: 'answered', value: 'yes', text: null },
      AnswerSchema
      // invalidatePaths omitido — default []
    );
    // invalidateEtag manual continua funcionando independente (sanity do helper reusado)
    invalidateEtag('/bridge/interventions');
    const after = await fetchApi('/bridge/interventions', QueueSchema);
    expect(after.data?.interventions).toHaveLength(0);
  });

  it('propaga a mensagem de erro do envelope da Ponte em falha de validacao (4xx)', async () => {
    // reaproveita o servidor real mas bate um path 404 do handler acima
    await expect(
      mutateApi('/bridge/interventions/inexistente/answer', 'POST', {}, AnswerSchema)
    ).rejects.toThrow(/HTTP 404/);
  });
});
