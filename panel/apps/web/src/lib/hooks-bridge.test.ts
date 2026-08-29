/**
 * Testes dos hooks da Ponte de intervencao humana (task 4.2.4).
 *
 * Sem jsdom/@testing-library neste repo (vitest.config.ts `environment:
 * 'node'` — mesmo padrao de `hooks-sessions.test.ts`). `useInterventions`/
 * `useAnswerIntervention` sao wrappers finos de `useQuery`/`useMutation`;
 * as opcoes e a `mutationFn` sao extraidas como funcoes puras e testadas
 * diretamente, inclusive o parse Zod real fim-a-fim via `fetch` mockado
 * (`vi.stubGlobal`).
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  interventionsQueuePath,
  interventionsQueryOptions,
  answerInterventionPath,
  answerInterventionMutationFn,
} from './hooks-bridge.js';
import { AUTO_REFRESH_MS } from './query.js';

describe('interventionsQueuePath — encoding de project (GET /bridge/interventions)', () => {
  it('sem project: path base, sem query string', () => {
    expect(interventionsQueuePath()).toBe('/bridge/interventions');
    expect(interventionsQueuePath('')).toBe('/bridge/interventions');
  });

  it('com project: adiciona query string encodada', () => {
    expect(interventionsQueuePath('cstk')).toBe('/bridge/interventions?project=cstk');
  });

  it('encoda caracteres especiais do project (defesa contra injecao via query)', () => {
    expect(interventionsQueuePath('foo bar/baz')).toBe('/bridge/interventions?project=foo%20bar%2Fbaz');
  });
});

describe('answerInterventionPath — encoding do questionId', () => {
  it('monta o path de answer', () => {
    expect(answerInterventionPath('q1')).toBe('/bridge/interventions/q1/answer');
  });

  it('encoda o questionId (defesa contra path-traversal via segmento)', () => {
    expect(answerInterventionPath('../etc/passwd')).toBe('/bridge/interventions/..%2Fetc%2Fpasswd/answer');
  });
});

describe('interventionsQueryOptions — refetchInterval EXPLICITO (contrato §9, sem SSE/WebSocket)', () => {
  it('usa AUTO_REFRESH_MS, nao o default do react-query', () => {
    expect(interventionsQueryOptions().refetchInterval).toBe(AUTO_REFRESH_MS);
  });

  it('pausa em background (refetchIntervalInBackground=false)', () => {
    expect(interventionsQueryOptions().refetchIntervalInBackground).toBe(false);
  });

  it('queryKey reflete o filtro de projeto (cache por project)', () => {
    expect(interventionsQueryOptions().queryKey).toEqual(['bridge-interventions', null]);
    expect(interventionsQueryOptions('cstk').queryKey).toEqual(['bridge-interventions', 'cstk']);
  });
});

// ---------------------------------------------------------------------------
// queryFn — parse Zod real fim-a-fim contra envelope MOCKADO fiel ao
// exemplo do contrato (mesma tecnica de hooks-sessions.test.ts).
// ---------------------------------------------------------------------------

function mockFetchOnce(body: unknown, status = 200) {
  const response = new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
  vi.stubGlobal('fetch', vi.fn(async () => response));
}

beforeEach(() => {
  vi.unstubAllGlobals();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('interventionsQueryOptions().queryFn — parse do envelope real', () => {
  it('parseia uma fila com um item aberto', async () => {
    mockFetchOnce({
      data: {
        interventions: [{
          questionId: 'q1',
          project: 'cstk',
          shortName: 'human-bridge',
          executionKind: 'feature-00c',
          kind: 'confirm',
          question: 'Prosseguir?',
          options: null,
          defaultValue: 'no',
          state: 'open',
          reachable: true,
          createdAt: '2026-08-29T10:00:00Z',
          expiresAt: '2026-08-29T10:05:00Z',
          waitingMs: 12000,
          appliedValue: null,
          untrustedText: null,
          resolvedAt: null,
        }],
        pagination: { limit: 20, offset: 0 },
      },
      meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '1' },
    });

    const result = await interventionsQueryOptions().queryFn();
    expect(result.data?.interventions).toHaveLength(1);
    expect(result.data?.interventions[0]?.kind).toBe('confirm');
    expect(result.meta.degraded).toBe(false);
  });

  it('parseia resposta degradada com data:null (bridge_unavailable)', async () => {
    mockFetchOnce({
      data: null,
      meta: { degraded: true, reason: 'bridge_unavailable', freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '1' },
    });

    const result = await interventionsQueryOptions().queryFn();
    expect(result.data).toBeNull();
    expect(result.meta.reason).toBe('bridge_unavailable');
  });
});

describe('answerInterventionMutationFn — usa mutateApi (nunca fetchApi) e invalida a fila', () => {
  it('envia o corpo correto e invalida o ETag da fila padrao apos sucesso', async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = typeof input === 'string' ? input : input.toString();
      expect(url).toBe('/api/v1/bridge/interventions/q1/answer');
      expect(init?.method).toBe('POST');
      expect(init?.headers).toMatchObject({ 'Content-Type': 'application/json' });
      const body = JSON.parse(init?.body as string);
      expect(body).toEqual({ resolution: 'answered', value: 'yes', text: null });
      // Nenhum If-None-Match — mutateApi nunca le ETag armazenado (contrato §8).
      expect((init?.headers as Record<string, string> | undefined)?.['If-None-Match']).toBeUndefined();
      return new Response(JSON.stringify({
        data: { questionId: 'q1', state: 'answered', appliedValue: 'yes', untrustedText: null, resolvedAt: '2026-08-29T10:01:00Z' },
        meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '1' },
      }), { status: 200, headers: { 'Content-Type': 'application/json', ETag: '"v2"' } });
    });
    vi.stubGlobal('fetch', fetchMock);

    const removedKeys: string[] = [];
    vi.stubGlobal('localStorage', {
      getItem: () => null,
      setItem: () => undefined,
      removeItem: (k: string) => removedKeys.push(k),
      clear: () => undefined,
      key: () => null,
      length: 0,
    } as unknown as Storage);

    const result = await answerInterventionMutationFn({
      questionId: 'q1',
      resolution: 'answered',
      value: 'yes',
      text: null,
    });

    expect(result.data?.state).toBe('answered');
    expect(fetchMock).toHaveBeenCalledTimes(1);
    // invalidateEtag('/bridge/interventions') remove as DUAS chaves (etag: + body:)
    expect(removedKeys).toContain('etag:/bridge/interventions');
  });
});
