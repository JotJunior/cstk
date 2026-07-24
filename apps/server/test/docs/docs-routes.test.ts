/**
 * Testes de integracao das rotas do Doc-Viewer (tasks 3.2.5, 3.3.3, 3.4.4).
 *
 * Ref: contracts/docs-api.md; quickstart.md Cenarios 4-9; spec.md FR-005..
 * FR-010, FR-012.
 *
 * Padrao de servidor de teste: mesmo de test/lib/routes.test.ts (Fastify
 * isolado registrando so as rotas necessarias). Projeto-alvo e um
 * diretorio temporario injetado via CSTK_PROJECT_PATHS (mesmo padrao de
 * test/lib/config.test.ts) — o filesystem real da feature vive la, nao
 * na knowledge.db (Principio I).
 */
import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach } from 'vitest';
import Fastify from 'fastify';
import type { FastifyInstance } from 'fastify';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync, chmodSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

async function buildServer(): Promise<FastifyInstance> {
  const server = Fastify({ logger: false });
  server.addHook('onSend', async (_req, reply) => {
    void reply.header('Content-Type', 'application/json; charset=utf-8');
  });

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

let server: FastifyInstance;
let tmpRoot: string;
let projectRoot: string;
let featureDir: string;

beforeAll(async () => {
  server = await buildServer();
});
afterAll(async () => {
  await server.close();
});

beforeEach(() => {
  tmpRoot = mkdtempSync(join(tmpdir(), 'cstk-docs-routes-'));
  projectRoot = join(tmpRoot, 'meu-projeto');
  featureDir = join(projectRoot, 'docs', 'specs', 'minha-feature');
  mkdirSync(featureDir, { recursive: true });
  process.env['CSTK_PROJECT_PATHS'] = `meu-projeto=${projectRoot}`;
});

afterEach(() => {
  delete process.env['CSTK_PROJECT_PATHS'];
  rmSync(tmpRoot, { recursive: true, force: true });
});

// ─── GET /docs — listagem (task 3.2.5) ───────────────────────────────────

describe('GET /features/:project/:feature/docs — listagem', () => {
  it('feature completa: todos os 6 artefatos fixos com produced:true (quickstart Cenario 4/6)', async () => {
    for (const name of ['spec.md', 'plan.md', 'research.md', 'data-model.md', 'quickstart.md', 'tasks.md']) {
      writeFileSync(join(featureDir, name), `# ${name}`);
    }
    const res = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.meta.degraded).toBe(false);
    expect(body.data.project).toBe('meu-projeto');
    expect(body.data.feature).toBe('minha-feature');
    const ownArtifacts = body.data.artifacts.filter((a: { scope: string }) => a.scope === 'feature');
    expect(ownArtifacts).toHaveLength(6);
    expect(ownArtifacts.every((a: { produced: boolean }) => a.produced === true)).toBe(true);
    // Listagem nunca inclui content (contrato: "Nenhum content, so metadados")
    expect(body.data.artifacts.every((a: Record<string, unknown>) => !('content' in a))).toBe(true);
  });

  it('feature parcial: artefatos ausentes vem produced:false, nunca erro (Cenario 5, FR-007)', async () => {
    writeFileSync(join(featureDir, 'spec.md'), '# spec');
    const res = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    const plan = body.data.artifacts.find((a: { artifactId: string }) => a.artifactId === 'plan');
    expect(plan.produced).toBe(false);
  });

  it('projeto sem entrada no mapa (CSTK_PROJECT_PATHS): degradado, nunca 5xx (Cenario 7, FR-012)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/features/projeto-desconhecido/minha-feature/docs' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.meta.degraded).toBe(true);
    expect(body.meta.reason).toBe('project-path-unresolved');
    expect(body.data).toBeNull();
  });

  it('project/feature com caracteres invalidos: 400 (nao 500)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/..%2f..%2fetc/docs' });
    expect(res.statusCode).toBe(400);
  });

  it('arquivo extra fora do mapa aparece na listagem (SC-002, Cenario 6)', async () => {
    writeFileSync(join(featureDir, 'spec.md'), '# spec');
    writeFileSync(join(featureDir, 'data-gaps.md'), '# gaps');
    const res = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs' });
    const body = res.json();
    const extra = body.data.artifacts.find((a: { artifactId: string }) => a.artifactId === 'data-gaps');
    expect(extra).toBeDefined();
    expect(extra.extra).toBe(true);
  });

  it('suporta ETag/304 (If-None-Match casando)', async () => {
    writeFileSync(join(featureDir, 'spec.md'), '# spec');
    const first = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs' });
    expect(first.statusCode).toBe(200);
    const etag = first.headers['etag'] as string | undefined;
    expect(etag).toBeTruthy();
    const second = await server.inject({
      method: 'GET',
      url: '/api/v1/features/meu-projeto/minha-feature/docs',
      headers: { 'if-none-match': etag! },
    });
    expect(second.statusCode).toBe(304);
  });
});

// ─── Artefatos de escopo PROJETO (briefing/constitution) ─────────────────

describe('docs de escopo projeto — briefing e constitution', () => {
  it('listagem inclui briefing/constitution do projeto na pagina da feature', async () => {
    mkdirSync(join(projectRoot, 'docs', '01-briefing-discovery'), { recursive: true });
    writeFileSync(join(projectRoot, 'docs', '01-briefing-discovery', 'briefing.md'), '# briefing');
    writeFileSync(join(projectRoot, 'docs', 'constitution.md'), '# constituicao');

    const res = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    const project = body.data.artifacts.filter((a: { scope: string }) => a.scope === 'project');
    expect(project.map((a: { artifactId: string }) => a.artifactId)).toEqual(['briefing', 'constitution']);
    expect(project.every((a: { produced: boolean }) => a.produced === true)).toBe(true);
  });

  it('conteudo de briefing e constitution e servido a partir da raiz do projeto', async () => {
    mkdirSync(join(projectRoot, 'docs', '01-briefing-discovery'), { recursive: true });
    writeFileSync(join(projectRoot, 'docs', '01-briefing-discovery', 'briefing.md'), '# Briefing\n\nVisao.');
    writeFileSync(join(projectRoot, 'docs', 'constitution.md'), '# Constituicao\n\nPrincipios.');

    const brief = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs/briefing' });
    expect(brief.statusCode).toBe(200);
    expect(brief.json().data.content).toBe('# Briefing\n\nVisao.');

    const cons = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs/constitution' });
    expect(cons.statusCode).toBe(200);
    expect(cons.json().data.content).toBe('# Constituicao\n\nPrincipios.');
  });

  it('projeto sem briefing/constitution: produced:false, content:null, 200 (FR-007)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs/constitution' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.data.produced).toBe(false);
    expect(body.data.content).toBeNull();
    expect(body.meta.degraded).toBe(false);
  });

  it('symlink em doc de projeto continua rejeitado (o confinamento so mudou de raiz, nao sumiu)', async () => {
    const outside = join(tmpRoot, 'fora.md');
    writeFileSync(outside, '# segredo fora do projeto');
    mkdirSync(join(projectRoot, 'docs'), { recursive: true });
    symlinkSync(outside, join(projectRoot, 'docs', 'constitution.md'));

    const res = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs/constitution' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.data.content).toBeNull();
    expect(body.meta.degraded).toBe(true);
    expect(body.meta.reason).toBe('artifact-rejected');
  });
});

// ─── GET /docs/:artifact — conteudo (task 3.3.3) ─────────────────────────

describe('GET /features/:project/:feature/docs/:artifact — conteudo', () => {
  it('artefato existente retorna content (Cenario 4)', async () => {
    writeFileSync(join(featureDir, 'spec.md'), '# Minha Spec\n\nConteudo.');
    const res = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs/spec' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.data.produced).toBe(true);
    expect(body.data.content).toBe('# Minha Spec\n\nConteudo.');
  });

  it('artefato do mapa fixo ausente retorna produced:false, content:null, 200 (Cenario 5, FR-007)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs/plan' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.data.produced).toBe(false);
    expect(body.data.content).toBeNull();
  });

  it('artefato extra fora do mapa e servido normalmente (SC-002)', async () => {
    writeFileSync(join(featureDir, 'data-gaps.md'), '# gaps reais');
    const res = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs/data-gaps' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.data.content).toBe('# gaps reais');
    expect(body.data.extra).toBe(true);
  });

  it('artifactId nao reconhecido retorna data:null (nao erro)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs/nao-existe-este-id' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.data).toBeNull();
    expect(body.meta.degraded).toBe(false);
  });

  it('projeto sem entrada no mapa: degradado, nunca 5xx', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/features/projeto-desconhecido/minha-feature/docs/spec' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.meta.degraded).toBe(true);
    expect(body.meta.reason).toBe('project-path-unresolved');
  });

  it('suporta ETag/304 para o conteudo de 1 artefato', async () => {
    writeFileSync(join(featureDir, 'spec.md'), '# spec');
    const first = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs/spec' });
    const etag = first.headers['etag'] as string | undefined;
    expect(etag).toBeTruthy();
    const second = await server.inject({
      method: 'GET',
      url: '/api/v1/features/meu-projeto/minha-feature/docs/spec',
      headers: { 'if-none-match': etag! },
    });
    expect(second.statusCode).toBe(304);
  });
});

// ─── Caminho de projeto inacessivel (task 5.2.3, Cenario 7, FR-012) ──────
// `describe.skipIf` porque root ignora permissoes de arquivo (accessSync
// nunca lancaria EACCES rodando como root) — evita falso-negativo em
// ambientes de CI que rodem containers como root.
const isRoot = typeof process.getuid === 'function' && process.getuid() === 0;

describe.skipIf(isRoot)('GET /docs — projeto com caminho inacessivel (Cenario 7, FR-012)', () => {
  it('listagem: projeto mapeado mas sem permissao de leitura ⇒ 200 degradado, reason=project-path-inaccessible', async () => {
    const restrictedRoot = join(tmpRoot, 'sem-permissao-list');
    mkdirSync(restrictedRoot, { recursive: true });
    chmodSync(restrictedRoot, 0o000);
    process.env['CSTK_PROJECT_PATHS'] = `projeto-restrito=${restrictedRoot}`;
    try {
      const res = await server.inject({ method: 'GET', url: '/api/v1/features/projeto-restrito/minha-feature/docs' });
      expect(res.statusCode).toBe(200); // nunca 5xx (Principio II)
      const body = res.json();
      expect(body.meta.degraded).toBe(true);
      expect(body.meta.reason).toBe('project-path-inaccessible');
      expect(body.data).toBeNull();
    } finally {
      chmodSync(restrictedRoot, 0o755); // restaurar antes do rmSync do afterEach
    }
  });

  it('conteudo de artefato: mesma degradacao no endpoint /docs/:artifact', async () => {
    const restrictedRoot = join(tmpRoot, 'sem-permissao-content');
    mkdirSync(restrictedRoot, { recursive: true });
    chmodSync(restrictedRoot, 0o000);
    process.env['CSTK_PROJECT_PATHS'] = `projeto-restrito-2=${restrictedRoot}`;
    try {
      const res = await server.inject({ method: 'GET', url: '/api/v1/features/projeto-restrito-2/minha-feature/docs/spec' });
      expect(res.statusCode).toBe(200);
      const body = res.json();
      expect(body.meta.degraded).toBe(true);
      expect(body.meta.reason).toBe('project-path-inaccessible');
    } finally {
      chmodSync(restrictedRoot, 0o755);
    }
  });
});

// ─── Seguranca (task 3.4.4, Cenario 9) ───────────────────────────────────

describe('GET /docs/:artifact — seguranca anti-traversal e anti-symlink (Cenario 9, FR-009)', () => {
  it('rejeita path traversal literal no :artifact (400, nunca conteudo fora da fronteira)', async () => {
    const res = await server.inject({
      method: 'GET',
      url: '/api/v1/features/meu-projeto/minha-feature/docs/' + encodeURIComponent('../../../etc/passwd'),
    });
    expect(res.statusCode).toBe(400);
  });

  it('rejeita traversal codificado (%2f) no :artifact (400)', async () => {
    const res = await server.inject({
      method: 'GET',
      url: '/api/v1/features/meu-projeto/minha-feature/docs/..%2f..%2fetc%2fpasswd',
    });
    expect(res.statusCode).toBe(400);
  });

  it('symlink escapando a raiz: nunca serve o conteudo real (degradado, content:null)', async () => {
    const secretFile = join(tmpRoot, 'segredo-fora-do-projeto.md');
    writeFileSync(secretFile, 'CONTEUDO_SECRETO_QUE_NUNCA_DEVE_APARECER');
    symlinkSync(secretFile, join(featureDir, 'evil.md'));

    // 1. A listagem PODE mostrar que "evil" existe (metadados apenas) —
    //    mas o conteudo NUNCA deve vazar.
    const listRes = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs' });
    const listBody = listRes.json();
    const evilEntry = listBody.data.artifacts.find((a: { artifactId: string }) => a.artifactId === 'evil');
    expect(evilEntry).toBeDefined();

    // 2. GARANTIA CENTRAL: buscar o conteudo NUNCA retorna os bytes do
    //    arquivo fora da raiz — nem em `data.content` nem em qualquer
    //    outro canto do payload bruto (checagem no corpo cru, nao so no
    //    campo esperado, para nao deixar passar um vazamento por outro campo).
    const contentRes = await server.inject({ method: 'GET', url: '/api/v1/features/meu-projeto/minha-feature/docs/evil' });
    expect(contentRes.statusCode).toBe(200); // nunca 5xx (Principio II)
    expect(contentRes.body).not.toContain('CONTEUDO_SECRETO_QUE_NUNCA_DEVE_APARECER');
    const contentBody = contentRes.json();
    expect(contentBody.data.content).toBeNull();
    expect(contentBody.meta.degraded).toBe(true);
    expect(contentBody.meta.reason).toBe('artifact-rejected');
  });

  it('project/feature com traversal no path param: 400 antes de qualquer acesso a filesystem', async () => {
    const res = await server.inject({
      method: 'GET',
      url: '/api/v1/features/' + encodeURIComponent('../../etc') + '/minha-feature/docs/spec',
    });
    expect(res.statusCode).toBe(400);
  });
});
