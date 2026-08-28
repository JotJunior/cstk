/**
 * 5.4 Roundtrip End-to-End OBRIGATORIO — servidor real (rotas reais
 * registradas, sem mock de handler) + knowledge.db real (fixture copiada
 * read-only da base do operador) + filesystem real (artefatos desta propria
 * feature, ja produzidos pelas ondas anteriores desta mesma execucao SDD).
 *
 * Ref: quickstart.md Cenario 10; contracts/docs-api.md; plan.md §Validacao
 * Zod; memorias `cstk-panel-dto-dual-definition` / `migration-gates-false-green`.
 *
 * Motivo (memoria migration-gates-false-green): 40 ondas historicas
 * mascararam um drift snake_case<->camelCase porque os testes parseavam
 * mocks, nao o payload real. Este arquivo faz chamada real ao handler e
 * compara o shape contra os schemas Zod declarados em @cstk-panel/shared-types
 * — qualquer drift de nome/tipo de campo falha o parse, nao so a asserção
 * manual de 1-2 campos.
 *
 * Dogfooding: `CSTK_PROJECT_PATHS` aponta para a RAIZ REAL deste monorepo, e
 * o "artefato" lido é o spec.md/plan.md/... REAL de
 * docs/specs/state-watchers-and-docs/ — produzidos por esta mesma execucao
 * SDD, nao uma fixture sintetica em tmpdir (diferente de docs-routes.test.ts,
 * que usa tmpdir isolado — ambas as abordagens sao validas; esta reforça o
 * caminho ponta-a-ponta contra o repositorio real).
 *
 * Padrao de servidor de teste identico a test/lib/roundtrip.test.ts (Fastify
 * + registro das rotas REAIS via import direto do modulo fonte + .inject(),
 * que exercita o mesmo pipeline de serializacao de uma chamada de rede real
 * sem precisar abrir uma porta TCP).
 *
 * Tasks 5.4.1 – 5.4.3 (5.4.4 é a suite parity*.test.ts, ja verde — ver
 * packages/shared-types/src/__tests__/parity.test.ts).
 */
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import Fastify from 'fastify';
import type { FastifyInstance } from 'fastify';
import { existsSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  ApiEnvelopeSchema,
  FeatureDocsListDTOSchema,
  FeatureDocDTOSchema,
} from '@cstk-panel/shared-types';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Mesma fixture real usada por test/lib/roundtrip.test.ts (copia read-only
// gerada por scripts/create-fixture.mjs a partir da knowledge.db do operador
// — este teste NUNCA escreve na base real nem na fixture).
const FIXTURE_DB = resolve(join(__dirname, '..', 'knowledge-fixture.db'));
const FIXTURE_EXISTS = existsSync(FIXTURE_DB);

// Raiz real deste monorepo: apps/server/test/integration -> apps/server/test
// -> apps/server -> apps -> <repo root>.
const REPO_ROOT = resolve(__dirname, '..', '..', '..', '..');
const FEATURE_DIR = join(REPO_ROOT, 'docs', 'specs', 'state-watchers-and-docs');
const REPO_HAS_FEATURE_DOCS = existsSync(join(FEATURE_DIR, 'spec.md'));

async function buildServer(dbPath: string, projectPaths: string): Promise<FastifyInstance> {
  process.env['CSTK_KNOWLEDGE_DB'] = dbPath;
  process.env['CSTK_PROJECT_PATHS'] = projectPaths;

  const server = Fastify({ logger: false });
  server.addHook('onSend', async (_req, reply) => {
    void reply.header('Content-Type', 'application/json; charset=utf-8');
    void reply.header('X-Content-Type-Options', 'nosniff');
    void reply.header('X-Frame-Options', 'DENY');
    void reply.header('Cache-Control', 'no-store');
  });

  // Import direto do modulo de rotas REAL (nenhum mock de handler).
  const { docsRoutes } = await import('../../src/routes/docs.js');
  await server.register(async (v1) => {
    await v1.register(docsRoutes);
  }, { prefix: '/api/v1' });

  server.setNotFoundHandler((_req, reply) => {
    return reply.status(404).send({
      data: null,
      meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '2' },
      error: 'Not found',
    });
  });

  await server.ready();
  return server;
}

describe.skipIf(!FIXTURE_EXISTS || !REPO_HAS_FEATURE_DOCS)(
  '5.4 Roundtrip E2E real — GET /docs (Cenario 10, OBRIGATORIO)',
  () => {
    let server: FastifyInstance;

    beforeAll(async () => {
      server = await buildServer(FIXTURE_DB, `cstk-panel=${REPO_ROOT}`);
    });
    afterAll(async () => {
      await server.close();
    });

    // 5.4.2 — GET /docs (listagem) contra payload REAL, validado por FeatureDocsListDTOSchema
    it('5.4.2 GET /docs retorna payload real validado por FeatureDocsListDTOSchema, camelCase exato', async () => {
      const res = await server.inject({
        method: 'GET',
        url: '/api/v1/features/cstk-panel/state-watchers-and-docs/docs',
      });
      expect(res.statusCode).toBe(200);

      const raw = res.json() as unknown;
      const EnvelopeSchema = ApiEnvelopeSchema(FeatureDocsListDTOSchema);
      const parsed = EnvelopeSchema.safeParse(raw);
      expect(
        parsed.success,
        `parse falhou: ${JSON.stringify(parsed.error?.issues?.slice(0, 5))}`
      ).toBe(true);

      const body = raw as { data: { artifacts: Record<string, unknown>[] } };
      expect(body.data.artifacts.length).toBeGreaterThan(0);
      for (const artifact of body.data.artifacts) {
        // Convencao de borda (camelCase exato, contracts/docs-api.md)
        expect('artifactId' in artifact).toBe(true);
        expect('fileName' in artifact).toBe(true);
        expect('produced' in artifact).toBe(true);
        expect('extra' in artifact).toBe(true);
        expect('artifact_id' in artifact).toBe(false);
        expect('file_name' in artifact).toBe(false);
        // Listagem nunca inclui content (contrato: "so metadados")
        expect('content' in artifact).toBe(false);
      }

      // spec.md ja foi produzido por esta propria execucao SDD (real).
      const specEntry = body.data.artifacts.find(a => a['artifactId'] === 'spec');
      expect(specEntry?.['produced']).toBe(true);
      expect(specEntry?.['fileName']).toBe('spec.md');
    });

    // 5.4.3 — GET /docs/:artifact contra payload REAL, validado por FeatureDocDTOSchema
    it('5.4.3 GET /docs/spec retorna payload real validado por FeatureDocDTOSchema, freshness/schemaVersion presentes', async () => {
      const res = await server.inject({
        method: 'GET',
        url: '/api/v1/features/cstk-panel/state-watchers-and-docs/docs/spec',
      });
      expect(res.statusCode).toBe(200);

      const raw = res.json() as unknown;
      const EnvelopeSchema = ApiEnvelopeSchema(FeatureDocDTOSchema);
      const parsed = EnvelopeSchema.safeParse(raw);
      expect(
        parsed.success,
        `parse falhou: ${JSON.stringify(parsed.error?.issues?.slice(0, 5))}`
      ).toBe(true);

      const body = raw as {
        data: { content: string | null; stage: string; extra: boolean };
        meta: { freshness: { mtime: string; maxIngestedAt: string }; schemaVersion: string };
      };
      expect(body.data.content).toBeTruthy();
      expect(body.data.content).toContain('state-watchers-and-docs');
      // stage/extra fazem parte do FeatureDocDTO obrigatorio (nota de
      // contracts/docs-api.md validada na task 4.2 — nao opcionais no wire).
      expect(body.data.stage).toBe('specify');
      expect(body.data.extra).toBe(false);
      // meta.freshness.{mtime,maxIngestedAt} e meta.schemaVersion presentes
      expect(typeof body.meta.freshness.mtime).toBe('string');
      expect(typeof body.meta.freshness.maxIngestedAt).toBe('string');
      expect(typeof body.meta.schemaVersion).toBe('string');
      expect(body.meta.schemaVersion.length).toBeGreaterThan(0);
    });

    // 5.4.3 — ETag/304 no roundtrip real
    it('5.4.3 segunda chamada com If-None-Match real retorna 304 sem corpo', async () => {
      const first = await server.inject({
        method: 'GET',
        url: '/api/v1/features/cstk-panel/state-watchers-and-docs/docs/spec',
      });
      expect(first.statusCode).toBe(200);
      const etag = first.headers['etag'] as string | undefined;
      expect(etag, 'ETag deve estar presente na resposta real').toBeDefined();

      if (etag) {
        const second = await server.inject({
          method: 'GET',
          url: '/api/v1/features/cstk-panel/state-watchers-and-docs/docs/spec',
          headers: { 'if-none-match': etag },
        });
        expect(second.statusCode).toBe(304);
        expect(second.rawPayload.length).toBe(0);
      }
    });
  }
);
