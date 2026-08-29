/**
 * Rotas do Doc-Viewer: leitura de artefatos de documentacao SDD de uma
 * feature diretamente do filesystem do projeto resolvido.
 * Ref: contracts/docs-api.md; spec.md FR-005..FR-010, FR-012; research.md
 * Decisions 7, 8; data-model.md Entity "Documentation Artifact"
 * Tasks 3.2, 3.3, 3.4
 *
 * Endpoints:
 *   GET /features/:project/:feature/docs            (listagem, task 3.2)
 *   GET /features/:project/:feature/docs/:artifact   (conteudo, task 3.3)
 *
 * Principio I (Read-Only Absoluto): fonte EXCLUSIVA e o filesystem
 * `<projectPath>/docs/specs/<feature>/` — a knowledge.db so e aberta (em
 * modo leitura) para computar `meta.freshness`/`schemaVersion` do envelope
 * e para o fallback de resolucao do caminho do projeto
 * (executions.target_project_path, schema v9 — lib/project-root.ts); uma
 * falha ao abrir o DB NAO degrada esta rota alem de desligar esse fallback
 * (os artefatos sao independentes da knowledge.db).
 */
import { accessSync, constants as fsConstants } from 'node:fs';
import { join } from 'node:path';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type Database from 'better-sqlite3';
import type { Freshness } from '@cstk-panel/shared-types';
import { openDb } from '../db/open.js';
import { wrap, wrapDegraded } from '../lib/envelope.js';
import { renderConvergeLedger } from '../docs/converge-ledger.js';
import { generateETag, etagMatches } from '../lib/etag.js';
import { loadConfig } from '../config.js';
import { resolveProjectRoot } from '../lib/project-root.js';
import {
  artifactRoots,
  buildFeatureDocsList,
  latestArtifactMtimeMs,
  rootForScope,
  type ArtifactRoots,
} from '../docs/artifact-map.js';
import { confineArtifactPath, readConfinedArtifact } from '../docs/confinement.js';

/** Identica ao regex anti-traversal de path params HTTP ja usado em
 *  FeatureParamSchema (routes/features.ts) e ExecParamSchema
 *  (routes/executions.ts) — aplicada tambem a `:artifact` (Decision 7). */
const SAFE_SEGMENT_RE = /^[^/\\.<>]+$/;

const DocsFeatureParamSchema = z.object({
  project: z.string().min(1).max(200).regex(SAFE_SEGMENT_RE, 'invalid project'),
  feature: z.string().min(1).max(200).regex(SAFE_SEGMENT_RE, 'invalid feature'),
});

const DocsArtifactParamSchema = DocsFeatureParamSchema.extend({
  artifact: z.string().min(1).max(200).regex(SAFE_SEGMENT_RE, 'invalid artifact'),
});

function emptyMeta() {
  return {
    degraded: false,
    reason: null,
    freshness: { mtime: '', maxIngestedAt: '' },
    schemaVersion: '2',
  };
}

type FeatureDirResolution =
  | { ok: true; roots: ArtifactRoots }
  | { ok: false; reason: 'project-path-unresolved' | 'project-path-inaccessible' };

/**
 * Resolve as raizes de leitura da pagina de uma feature — a raiz do projeto
 * (briefing/constitution) e `<projectRoot>/docs/specs/<feature>` (artefatos da
 * feature) — a partir do nome logico do projeto (FR-008/FR-012), via cadeia
 * CSTK_PROJECT_PATHS > knowledge.db v9 (resolveProjectRoot). NUNCA lanca. A
 * auséncia do proprio subdiretorio da FEATURE (feature nunca rodou
 * `/specify`) NAO e degradacao — vira produced:false uniforme em
 * artifact-map.ts (Principio II).
 */
function resolveFeatureDir(
  db: Database.Database | null,
  project: string,
  feature: string
): FeatureDirResolution {
  const projectRoot = resolveProjectRoot(db, project);
  if (!projectRoot) return { ok: false, reason: 'project-path-unresolved' };
  try {
    accessSync(projectRoot, fsConstants.R_OK);
  } catch {
    return { ok: false, reason: 'project-path-inaccessible' };
  }
  return { ok: true, roots: artifactRoots(projectRoot, feature) };
}

export async function docsRoutes(server: FastifyInstance): Promise<void> {
  const config = loadConfig();

  // ─── GET /features/:project/:feature/docs — listagem (task 3.2) ─────────
  server.get('/features/:project/:feature/docs', async (request, reply) => {
    const paramResult = DocsFeatureParamSchema.safeParse(request.params);
    if (!paramResult.success) {
      return reply.status(400).send({ data: null, meta: emptyMeta(), error: 'Invalid project or feature name' });
    }
    const { project, feature } = paramResult.data;

    // DB aberto ANTES da resolucao: alimenta o fallback de caminho via
    // knowledge.db v9 (lib/project-root.ts) alem do meta do envelope.
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    const db = openResult.ok ? openResult.db : null;
    try {
      const resolved = resolveFeatureDir(db, project, feature);
      if (!resolved.ok) {
        return reply.status(200).send(wrapDegraded(resolved.reason, config.dbPath));
      }

      const artifacts = buildFeatureDocsList(resolved.roots);
      const data = { project, feature, artifacts };
      const envelope = wrap(data, {}, config.dbPath, db);

      // ETag deriva do mtime dos ARQUIVOS (contracts/docs-api.md nota de
      // frescor), NAO de envelope.meta.freshness (que reflete a knowledge.db).
      const latestMs = latestArtifactMtimeMs(resolved.roots, artifacts);
      const fileFreshness: Freshness = {
        mtime: latestMs !== null ? new Date(latestMs).toISOString() : '',
        maxIngestedAt: '',
      };
      const etag = generateETag(fileFreshness);
      const ifNoneMatch = request.headers['if-none-match'] as string | undefined;
      if (etag && etagMatches(ifNoneMatch, etag)) return reply.status(304).send();
      if (etag) void reply.header('ETag', etag);

      return reply.status(200).send(envelope);
    } finally {
      if (db) db.close();
    }
  });

  // ─── GET /features/:project/:feature/docs/:artifact — conteudo (task 3.3+3.4) ─
  server.get('/features/:project/:feature/docs/:artifact', async (request, reply) => {
    const paramResult = DocsArtifactParamSchema.safeParse(request.params);
    if (!paramResult.success) {
      return reply.status(400).send({ data: null, meta: emptyMeta(), error: 'Invalid project, feature or artifact name' });
    }
    const { project, feature, artifact } = paramResult.data;

    // DB aberto ANTES da resolucao (mesmo motivo da rota de listagem).
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    const db = openResult.ok ? openResult.db : null;
    try {
      const resolved = resolveFeatureDir(db, project, feature);
      if (!resolved.ok) {
        return reply.status(200).send(wrapDegraded(resolved.reason, config.dbPath));
      }

      const artifacts = buildFeatureDocsList(resolved.roots);
      const entry = artifacts.find(a => a.artifactId === artifact);

      if (!entry) {
        // artifactId nao reconhecido (nem mapa fixo, nem extra descoberto) —
        // mesmo padrao de "recurso ausente" ja usado em executions.ts
        // (data:null, 200) para um execucaoId sintaticamente valido mas
        // sem correspondencia.
        return reply.status(200).send(wrap(null, {}, config.dbPath, db));
      }

      if (!entry.produced) {
        // FR-007 — "ainda nao produzido": sucesso, nunca erro
        const envelope = wrap({ ...entry, content: null }, {}, config.dbPath, db);
        return reply.status(200).send(envelope);
      }

      // Confinamento na raiz do PROPRIO escopo do artefato: `docs/specs/
      // <feature>/` para artefatos da feature, raiz do projeto para
      // briefing/constitution (que vivem fora de docs/specs/). `fileName`
      // nunca vem do cliente — sai do mapa fixo/listagem do servidor.
      const artifactRoot = rootForScope(resolved.roots, entry.scope);
      const confineResult = confineArtifactPath(artifactRoot, join(artifactRoot, ...entry.fileName.split('/')));
      if (!confineResult.ok) {
        if (confineResult.reason === 'too-large') {
          const envelope = wrap({ ...entry, content: null }, {}, config.dbPath, db);
          envelope.meta.degraded = true;
          envelope.meta.reason = 'artifact-too-large';
          return reply.status(200).send(envelope);
        }
        if (confineResult.reason === 'not-found') {
          // TOCTOU: existia na listagem, sumiu antes da leitura — trata
          // como "ainda nao produzido" (FR-007); nao e anomalia de seguranca.
          const envelope = wrap({ ...entry, produced: false, content: null }, {}, config.dbPath, db);
          return reply.status(200).send(envelope);
        }
        // symlink-rejected / path-escapes-root — anomalia de seguranca
        // (Decision 7). Log interno com o motivo especifico; resposta
        // externa generica (nao vazar detalhe de exploit ao cliente).
        server.log.warn(
          { project, feature, artifact, reason: confineResult.reason },
          'docs: leitura de artefato rejeitada pelo guard de confinamento'
        );
        const envelope = wrap({ ...entry, content: null }, {}, config.dbPath, db);
        envelope.meta.degraded = true;
        envelope.meta.reason = 'artifact-rejected';
        return reply.status(200).send(envelope);
      }

      const raw = readConfinedArtifact(confineResult.realPath);
      // `converge-report.md` e um LEDGER de marcadores HTML, nao prosa —
      // servido cru renderiza uma pagina em branco. Traduz para tabela
      // legivel; devolve `null` (e servimos o original) quando nao ha
      // marcador algum. Ver docs/converge-ledger.ts.
      const content =
        entry.artifactId === 'converge-report' && raw !== null
          ? (renderConvergeLedger(raw) ?? raw)
          : raw;
      const envelope = wrap({ ...entry, content }, {}, config.dbPath, db);

      const fileFreshness: Freshness = { mtime: new Date(confineResult.mtimeMs).toISOString(), maxIngestedAt: '' };
      const etag = generateETag(fileFreshness);
      const ifNoneMatch = request.headers['if-none-match'] as string | undefined;
      if (etag && etagMatches(ifNoneMatch, etag)) return reply.status(304).send();
      if (etag) void reply.header('ETag', etag);

      return reply.status(200).send(envelope);
    } finally {
      if (db) db.close();
    }
  });
}
