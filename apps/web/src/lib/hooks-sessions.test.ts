/**
 * Testes dos hooks de Session Tail (task 6.1.3; contracts/sessions-api.md).
 *
 * Sem jsdom/@testing-library neste repo (vitest.config.ts `environment:
 * 'node'` — ver hooks-docs.test.ts para o mesmo padrao). `useSessions`/
 * `useSessionTail` sao wrappers finos de `useQuery(options)`; as opcoes
 * (`queryKey`/`queryFn`/`refetchInterval`) sao extraidas como funcoes puras
 * (`sessionsQueryOptions`/`sessionTailQueryOptions`) e testadas diretamente
 * — inclusive o parse Zod real fim-a-fim via `queryFn()` com `fetch`
 * mockado (`vi.stubGlobal`).
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  sessionsListPath,
  sessionTailPath,
  sessionsQueryOptions,
  sessionTailQueryOptions,
} from './hooks.js';
import { AUTO_REFRESH_MS } from './query.js';

describe('sessionsListPath — encoding/clamp de params (GET /sessions)', () => {
  it('sem params quando live=true (default) e sem limit', () => {
    expect(sessionsListPath()).toBe('/sessions');
    expect(sessionsListPath(true)).toBe('/sessions');
  });

  it('adiciona live=false quando live e false', () => {
    expect(sessionsListPath(false)).toBe('/sessions?live=false');
  });

  it('adiciona limit quando informado', () => {
    expect(sessionsListPath(true, 50)).toBe('/sessions?limit=50');
  });

  it('combina live=false e limit', () => {
    expect(sessionsListPath(false, 10)).toBe('/sessions?live=false&limit=10');
  });
});

describe('sessionTailPath — encoding do sessionId (GET /sessions/:sessionId/tail)', () => {
  it('monta o path sem query quando lines nao informado', () => {
    expect(sessionTailPath('11111111-2222-4333-8444-555555555555'))
      .toBe('/sessions/11111111-2222-4333-8444-555555555555/tail');
  });

  it('adiciona ?lines quando informado', () => {
    expect(sessionTailPath('abc', 50)).toBe('/sessions/abc/tail?lines=50');
  });

  it('encoda o sessionId (defesa contra path-traversal via segmento)', () => {
    expect(sessionTailPath('../etc/passwd')).toBe('/sessions/..%2Fetc%2Fpasswd/tail');
  });
});

describe('sessionsQueryOptions — refetchInterval EXPLICITO (FR-002, task 6.1.2)', () => {
  it('usa AUTO_REFRESH_MS, nao o default do react-query', () => {
    const opts = sessionsQueryOptions();
    expect(opts.refetchInterval).toBe(AUTO_REFRESH_MS);
  });

  it('queryKey reflete os parametros (cache por live/limit)', () => {
    expect(sessionsQueryOptions(true, 10).queryKey).toEqual(['sessions', true, 10]);
    expect(sessionsQueryOptions(false).queryKey).toEqual(['sessions', false, undefined]);
  });
});

describe('sessionTailQueryOptions — refetchInterval + enabled (FR-002/FR-003)', () => {
  it('usa AUTO_REFRESH_MS', () => {
    expect(sessionTailQueryOptions('s1').refetchInterval).toBe(AUTO_REFRESH_MS);
  });

  it('enabled=false quando sessionId vazio (evita fetch com path invalido)', () => {
    expect(sessionTailQueryOptions('').enabled).toBe(false);
    expect(sessionTailQueryOptions('s1').enabled).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// queryFn — parse Zod real fim-a-fim contra envelope MOCKADO fiel ao
// exemplo de contracts/sessions-api.md (mesma tecnica de hooks-docs.test.ts)
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

describe('sessionsQueryOptions().queryFn — parse do envelope real', () => {
  it('parseia uma lista de sessoes valida', async () => {
    mockFetchOnce({
      data: {
        sessions: [
          {
            sessionId: '11111111-2222-4333-8444-555555555555',
            projectPath: '/Users/jot/Projects/foo',
            projectSlug: '-Users-jot-Projects-foo',
            lastActivityAt: '2026-08-27T10:00:00Z',
            live: true,
            sizeBytes: 4096,
          },
        ],
        total: 1,
        scannedAt: '2026-08-27T10:00:05Z',
        scrubMode: 'cstk+internal',
      },
      meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '2' },
    });

    const result = await sessionsQueryOptions().queryFn();
    expect(result.data?.sessions).toHaveLength(1);
    expect(result.data?.sessions[0]?.sessionId).toBe('11111111-2222-4333-8444-555555555555');
    expect(result.meta.degraded).toBe(false);
  });

  it('parseia resposta degradada com data:null (sessions-root-missing)', async () => {
    mockFetchOnce({
      data: null,
      meta: { degraded: true, reason: 'sessions-root-missing', freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '2' },
    });

    const result = await sessionsQueryOptions().queryFn();
    expect(result.data).toBeNull();
    expect(result.meta.reason).toBe('sessions-root-missing');
  });
});

describe('sessionTailQueryOptions().queryFn — parse do envelope real', () => {
  it('parseia entries com uuid/timestamp/role nulos (campos opcionais do DTO)', async () => {
    mockFetchOnce({
      data: {
        sessionId: 's1',
        entries: [
          { uuid: null, type: 'user', timestamp: null, role: null, text: 'oi', textTruncated: false,
            kind: 'text', toolName: null },
        ],
        requestedLines: 200,
        returnedLines: 1,
        skippedLines: 0,
        filteredEntries: 0,
        truncatedByBytes: false,
        windowTruncated: false,
        live: true,
        lastActivityAt: '2026-08-27T10:00:00Z',
        scrubMode: 'internal',
      },
      meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '2' },
    });

    const result = await sessionTailQueryOptions('s1').queryFn();
    expect(result.data?.entries[0]?.text).toBe('oi');
    expect(result.data?.entries[0]?.uuid).toBeNull();
  });
});
