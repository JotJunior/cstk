/**
 * Testes do doc-viewer no cliente (task 4.2.3): `fetchApi` + parse Zod dos
 * DTOs de 1.2 (`FeatureDocsListDTOSchema`/`FeatureDocDTOSchema`) contra um
 * envelope MOCKADO fiel ao exemplo real de contracts/docs-api.md.
 *
 * `useFeatureDocs`/`useFeatureDocContent` (hooks.ts) sao wrappers finos de
 * `useQuery({ queryFn: () => fetchApi(url, schema) })` — chamar um hook React
 * fora de render (sem QueryClientProvider) viola as Rules of Hooks (este
 * repo nao tem jsdom/@testing-library configurados, ver vitest.config.ts
 * `environment: 'node'` + hooks-schemas.test.ts, que testa so os SCHEMAS
 * pelo mesmo motivo). Por isso o teste exercita a MESMA chamada que o
 * queryFn dos hooks faz (`fetchApi(path, schema)`) diretamente — cobre o
 * parse Zod real fim-a-fim (nao so a forma do schema em isolado) com
 * `fetch`/`Response` NATIVOS do Node 22 (engines >=20 — sem dependencia
 * nova), mockados via `vi.stubGlobal`.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { fetchApi } from './api.js';
import { featureDocsPath, featureDocPath } from './hooks.js';
import { FeatureDocsListDTOSchema, FeatureDocDTOSchema } from '@cstk-panel/shared-types';

describe('featureDocsPath / featureDocPath — encoding de segmentos (task 4.2.2)', () => {
  it('monta o path da listagem sem encoding para nomes simples', () => {
    expect(featureDocsPath('cstk-panel', 'state-watchers-and-docs'))
      .toBe('/features/cstk-panel/state-watchers-and-docs/docs');
  });

  it('encoda "/" e espaco em project/feature (anti path-traversal via segmento)', () => {
    expect(featureDocsPath('a/b', 'c d')).toBe('/features/a%2Fb/c%20d/docs');
  });

  it('monta o path de conteudo encodando os 3 segmentos', () => {
    expect(featureDocPath('cstk-panel', 'state-watchers-and-docs', 'spec'))
      .toBe('/features/cstk-panel/state-watchers-and-docs/docs/spec');
    expect(featureDocPath('p', 'f', 'contracts/x'))
      .toBe('/features/p/f/docs/contracts%2Fx');
  });
});

function mockFetchOnce(body: unknown, init?: { status?: number; etag?: string }) {
  const status = init?.status ?? 200;
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (init?.etag) headers.ETag = init.etag;
  // Fetch spec (WHATWG) proibe body em respostas 204/205/304 — o construtor
  // nativo `Response` do Node 22 (undici) ja aplica essa validacao e lanca
  // se tentarmos passar corpo com status 304 (confirmado empiricamente: um
  // 304 real de servidor tambem nunca tem corpo, e fetchApi nem tenta
  // ler-lo nesse caso — le do bodyCache local).
  const responseBody = status === 304 ? null : JSON.stringify(body);
  const response = new Response(responseBody, { status, headers });
  const fn = vi.fn(async () => response);
  vi.stubGlobal('fetch', fn);
  return fn;
}

beforeEach(() => {
  vi.unstubAllGlobals();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('doc-viewer client — listagem (FeatureDocsListDTOSchema)', () => {
  it('parseia o exemplo real de contracts/docs-api.md (mapa fixo + produced true/false)', async () => {
    const envelope = {
      data: {
        project: 'cstk-panel',
        feature: 'state-watchers-and-docs',
        artifacts: [
          { stage: 'specify', artifactId: 'spec', scope: 'feature', fileName: 'spec.md', produced: true, extra: false },
          { stage: 'plan', artifactId: 'plan', scope: 'feature', fileName: 'plan.md', produced: true, extra: false },
          { stage: 'plan', artifactId: 'research', scope: 'feature', fileName: 'research.md', produced: true, extra: false },
          { stage: 'plan', artifactId: 'data-model', scope: 'feature', fileName: 'data-model.md', produced: true, extra: false },
          { stage: 'plan', artifactId: 'quickstart', scope: 'feature', fileName: 'quickstart.md', produced: true, extra: false },
          { stage: 'create-tasks', artifactId: 'tasks', scope: 'feature', fileName: 'tasks.md', produced: false, extra: false },
        ],
      },
      meta: { degraded: false, reason: null, freshness: { mtime: '2026-07-15T00:00:00Z', maxIngestedAt: '' }, schemaVersion: '8' },
    };
    const fetchMock = mockFetchOnce(envelope);

    const result = await fetchApi(
      '/features/cstk-panel/state-watchers-and-docs/docs',
      FeatureDocsListDTOSchema
    );

    expect(fetchMock).toHaveBeenCalledWith(
      '/api/v1/features/cstk-panel/state-watchers-and-docs/docs',
      expect.objectContaining({ headers: expect.objectContaining({ Accept: 'application/json' }) })
    );
    expect(result.data?.artifacts).toHaveLength(6);
    expect(result.data?.artifacts[0]).toEqual({ stage: 'specify', artifactId: 'spec', scope: 'feature', fileName: 'spec.md', produced: true, extra: false });
    // FR-007 — artefato do mapa fixo ainda nao produzido: sucesso, nao erro
    expect(result.data?.artifacts[5]).toMatchObject({ artifactId: 'tasks', produced: false });
  });

  it('featureDocsPath + fetchApi ponta-a-ponta: URL final e a esperada pelo backend', async () => {
    const fetchMock = mockFetchOnce({
      data: { project: 'a/b', feature: 'c d', artifacts: [] },
      meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '8' },
    });
    await fetchApi(featureDocsPath('a/b', 'c d'), FeatureDocsListDTOSchema);
    expect(fetchMock).toHaveBeenCalledWith('/api/v1/features/a%2Fb/c%20d/docs', expect.anything());
  });

  it('rejeita envelope com artefato faltando campo obrigatorio (guard de contrato)', async () => {
    mockFetchOnce({
      data: { project: 'p', feature: 'f', artifacts: [{ stage: 'specify', artifactId: 'spec', produced: true, extra: false }] },
      meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '8' },
    });
    await expect(
      fetchApi('/features/p/f/docs', FeatureDocsListDTOSchema)
    ).rejects.toThrow();
  });

  it('degradado (project-path-inaccessible): data:null + meta.degraded:true, nunca lanca', async () => {
    mockFetchOnce({
      data: null,
      meta: { degraded: true, reason: 'project-path-inaccessible', freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '8' },
    });
    const result = await fetchApi('/features/p/f/docs', FeatureDocsListDTOSchema.nullable());
    expect(result.data).toBeNull();
    expect(result.meta.degraded).toBe(true);
    expect(result.meta.reason).toBe('project-path-inaccessible');
  });
});

describe('doc-viewer client — conteudo de 1 artefato (FeatureDocDTOSchema)', () => {
  it('produced:true retorna content (markdown bruto, UNTRUSTED)', async () => {
    // Nota: contracts/docs-api.md abrevia o exemplo de resposta sem
    // `stage`/`extra`, mas o wire real (routes/docs.ts `{ ...entry, content }`,
    // onde `entry` vem de `buildFeatureDocsList`) SEMPRE inclui os 2 campos —
    // confirmado empiricamente: sem eles o parse Zod falha (ZodError
    // Required em data.stage/data.extra), o que este teste tambem trava.
    mockFetchOnce({
      data: { stage: 'specify', artifactId: 'spec', scope: 'feature', fileName: 'spec.md', produced: true, extra: false, content: '# Feature Specification: X\n\n...' },
      meta: { degraded: false, reason: null, freshness: { mtime: '2026-07-15T00:00:00Z', maxIngestedAt: '' }, schemaVersion: '8' },
    });
    const result = await fetchApi(
      '/features/cstk-panel/state-watchers-and-docs/docs/spec',
      FeatureDocDTOSchema.nullable()
    );
    expect(result.data?.produced).toBe(true);
    expect(result.data?.content).toContain('Feature Specification');
  });

  it('produced:false retorna content:null — sucesso, nunca erro (FR-007)', async () => {
    mockFetchOnce({
      data: { stage: 'plan', artifactId: 'plan', scope: 'feature', fileName: 'plan.md', produced: false, extra: false, content: null },
      meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '8' },
    });
    const result = await fetchApi(
      '/features/cstk-panel/state-watchers-and-docs/docs/plan',
      FeatureDocDTOSchema.nullable()
    );
    expect(result.data?.produced).toBe(false);
    expect(result.data?.content).toBeNull();
  });

  it('artifactId nao reconhecido: data:null (mesmo padrao de executions.ts)', async () => {
    mockFetchOnce({
      data: null,
      meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '8' },
    });
    const result = await fetchApi(
      '/features/cstk-panel/state-watchers-and-docs/docs/inexistente',
      FeatureDocDTOSchema.nullable()
    );
    expect(result.data).toBeNull();
  });

  it('304 (ETag casando) retorna o corpo cacheado sem novo parse', async () => {
    const path = '/features/cstk-panel/state-watchers-and-docs/docs/spec-etag-test';
    mockFetchOnce(
      { data: { stage: 'specify', artifactId: 'spec', scope: 'feature', fileName: 'spec.md', produced: true, extra: false, content: '# v1' }, meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '8' } },
      { etag: 'W/"v1"' }
    );
    const first = await fetchApi(path, FeatureDocDTOSchema.nullable());
    expect(first.data?.content).toBe('# v1');

    mockFetchOnce({}, { status: 304 });
    const second = await fetchApi(path, FeatureDocDTOSchema.nullable());
    expect(second.data?.content).toBe('# v1'); // veio do cache, nao do body vazio do 304
  });
});
