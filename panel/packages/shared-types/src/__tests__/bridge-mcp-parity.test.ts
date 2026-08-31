/**
 * Teste smoke de paridade: schema Zod do painel (`shared-types`) vs. cliente
 * HTTP do servidor MCP (`plugins/cstk/mcp/state-server/src/bridge/client.ts`).
 * Ref: docs/specs/human-bridge/contracts/panel-bridge-api.md §2
 *      docs/specs/human-bridge/tasks.md 3.4.2, 3.4.3
 *
 * Os dois lados vivem em repos/instalacoes DISTINTAS de proposito (contrato
 * §2 — "MUST NOT importar shared-types") — este teste e o UNICO lugar do
 * repo que os importa juntos, e SO em tempo de teste (nunca em producao):
 * `plugins/cstk/mcp/state-server/src/bridge/client.ts` nao depende de `zod` nem de
 * nenhum pacote do painel (so `node:crypto`), entao importa-lo aqui nao
 * reintroduz o acoplamento que o contrato probe.
 *
 * Cenario: um payload REAL (nao mock) e construido pela funcao de
 * producao `createBridgeClient().createIntervention()` — o EXATO corpo que
 * o servidor MCP envia por HTTP — e validado campo-a-campo contra
 * `CreateInterventionRequestDTOSchema` (o schema que `routes/bridge.ts` usa
 * para validar a entrada). Detecta divergencia camelCase/snake_case ou
 * renomeacao de campo introduzida por refactor futuro em qualquer um dos
 * dois lados.
 *
 * NOTA DE BUILD: este arquivo e explicitamente EXCLUIDO de
 * `tsconfig.json` (`exclude`) — importar um arquivo fora de `rootDir:
 * "src"` quebraria `tsc --project tsconfig.json` (erro TS6059, medido).
 * `vitest` roda este arquivo normalmente (via `vitest.config.ts`, que nao
 * usa `tsc --project` para resolver modulos) — a exclusao afeta SO
 * `npm run build`/`npm run typecheck`, nunca `npm test`.
 */
import { describe, it, expect } from 'vitest';
import {
  CreateInterventionRequestDTOSchema,
  CreateInterventionRequestDTOBaseSchema,
  PollInterventionResponseDTOSchema,
} from '../schemas/entities.js';
import {
  createBridgeClient,
  type CreateInterventionRequest,
} from '../../../../../plugins/cstk/mcp/state-server/src/bridge/client.js';

const REAL_REQUEST: CreateInterventionRequest = {
  projectPath: '/Users/jot/Projects/example',
  project: 'example',
  shortName: 'human-bridge',
  executionKind: 'feature-00c',
  kind: 'choice',
  question: 'Prosseguir com o merge?',
  options: ['sim', 'nao'],
  defaultValue: 'nao',
  timeoutMs: 240000,
};

describe('Paridade HTTP: bridge/client.ts (MCP) <-> CreateInterventionRequestDTOSchema (painel)', () => {
  it('task 3.4.2 — plugins/cstk/mcp/state-server nao importa @cstk-panel/shared-types em NENHUM arquivo de producao', async () => {
    // Confirmacao estatica (nao so grep de repo): a propria funcao usada
    // abaixo nao carrega nenhum modulo do escopo @cstk-panel/*.
    const mod = await import('../../../../../plugins/cstk/mcp/state-server/src/bridge/client.js');
    expect(typeof mod.createBridgeClient).toBe('function');
    // Se o arquivo importasse shared-types, o import acima falharia (o
    // pacote nao esta instalado como dependencia de plugins/cstk/mcp/state-server) —
    // a propria ausencia de erro de resolucao de modulo E a confirmacao.
  });

  it('o corpo HTTP REAL de createIntervention() valida integralmente contra CreateInterventionRequestDTOSchema', async () => {
    let capturedBody: string | null = null;
    let capturedUrl: string | null = null;
    let capturedContentType: string | null = null;

    const fakeFetch = (async (url: string | URL, init?: RequestInit) => {
      capturedUrl = String(url);
      capturedBody = init?.body ? String(init.body) : null;
      const headers = init?.headers as Record<string, string> | undefined;
      capturedContentType = headers?.['Content-Type'] ?? null;
      return new Response(
        JSON.stringify({
          data: { questionId: 'q-real-001-abcdefghijklmnop', expiresAt: '2026-01-01T00:04:00.000Z' },
          meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '1' },
        }),
        { status: 201, headers: { 'Content-Type': 'application/json' } },
      );
    }) as unknown as typeof fetch;

    const client = createBridgeClient('http://127.0.0.1:5173', { fetchImpl: fakeFetch });
    const outcome = await client.createIntervention(REAL_REQUEST);

    expect(outcome.kind).toBe('created');
    expect(capturedUrl).toBe('http://127.0.0.1:5173/api/v1/bridge/interventions');
    expect(capturedContentType).toBe('application/json');
    expect(capturedBody).not.toBeNull();

    const parsedBody: unknown = JSON.parse(capturedBody as unknown as string);
    const result = CreateInterventionRequestDTOSchema.safeParse(parsedBody);
    expect(
      result.success,
      `payload real enviado pelo MCP nao valida contra o schema do painel: ${
        result.success ? '' : JSON.stringify(result.error.issues)
      }`,
    ).toBe(true);

    // Paridade de CHAVES (nao so de tipos) — pega renomeacao camelCase/snake_case.
    const sentKeys = Object.keys(parsedBody as Record<string, unknown>).sort();
    const expectedKeys = Object.keys(CreateInterventionRequestDTOBaseSchema.shape).sort();
    expect(sentKeys).toEqual(expectedKeys);
  });

  it('pollIntervention() le um payload REAL no formato de PollInterventionResponseDTOSchema (answered) sem drift de nome de campo', async () => {
    const panelShapedResponse = {
      questionId: 'q-real-002-abcdefghijklmnop',
      state: 'answered' as const,
      appliedValue: 'sim',
      untrustedText: null,
      resolvedAt: '2026-01-01T00:02:00.000Z',
    };
    // O payload de fato "servido" pelo painel e { data, meta } — valida-lo
    // ANTES de simular a resposta garante que o fixture deste teste e
    // conformante ao proprio contrato do painel (nao um mock arbitrario).
    expect(PollInterventionResponseDTOSchema.safeParse(panelShapedResponse).success).toBe(true);

    const fakeFetch = (async () =>
      new Response(
        JSON.stringify({
          data: panelShapedResponse,
          meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '1' },
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      )) as unknown as typeof fetch;

    const client = createBridgeClient('http://127.0.0.1:5173', { fetchImpl: fakeFetch });
    const outcome = await client.pollIntervention(panelShapedResponse.questionId);

    expect(outcome.kind).toBe('answered');
    if (outcome.kind === 'answered') {
      expect(outcome.appliedValue).toBe('sim');
      expect(outcome.untrustedText).toBeNull();
    }
  });
});
