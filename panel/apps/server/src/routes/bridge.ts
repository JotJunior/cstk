/**
 * Rotas `POST`/`GET /api/v1/bridge/*` — Ponte de intervencao humana.
 * Ref: docs/specs/human-bridge/contracts/panel-bridge-api.md (integral)
 *      docs/specs/human-bridge/data-model.md §Entity: Intervention
 *      panel/docs/constitution.md Principio I ("Read-Only sobre o Corpus" —
 *      emenda 2.0.0, "A excecao da Ponte")
 * Tasks: 3.1.1 - 3.1.10, 3.3.1 - 3.3.5
 *
 * PRIMEIRA superficie nao-`GET` do painel. Autorizada exclusivamente pelos
 * quatro MUST da emenda 2.0.0: (1) escrita confinada a `bridge.db`, conexao
 * SEPARADA read-write; (2) rotas nao-`GET` SO sob `/api/v1/bridge/*`; (3) a
 * Ponte MUST NOT gravar decisao/bloqueio/onda/execucao no corpus — o
 * registro canonico e do agente, via `.operator_answers[]`; (4) roteamento
 * por `session_id`, nunca `execution_id` (honrado ANTES desta camada, no
 * servidor MCP — este arquivo nunca ve `session_id`).
 *
 * Degradacao (Principio II, contrato §3/§3.1): `bridge.db` ausente,
 * ilegivel, ou qualquer falha ao abrir/escrever responde `200` com
 * `meta.degraded=true` — NUNCA `5xx` por condicao de dado. Erro de
 * VALIDACAO de request continua `4xx` (nao e condicao de dado).
 */
import { existsSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import cors from '@fastify/cors';
import type Database from 'better-sqlite3';
import {
  CreateInterventionRequestDTOSchema,
  AnswerInterventionRequestDTOSchema,
} from '@cstk-panel/shared-types';
import { openBridgeDb, resolveBridgeDbPath } from '../db/bridge.js';
import { wrapBridge, wrapBridgeDegraded, bridgeErrorEnvelope } from '../lib/envelope.js';
import { safeParsePagination } from '../lib/pagination.js';
import { loadConfig } from '../config.js';
import {
  sanitizeUntrustedFields,
  sanitizeUntrustedInput,
  QUESTION_MAX_BYTES,
  OPTION_MAX_BYTES,
  TEXT_MAX_BYTES,
} from '../lib/bridge-sanitize.js';
import { z } from 'zod';

// ---------------------------------------------------------------------------
// Augmentacao de tipo p/ o override por rota de `@fastify/cors`
// (`req.routeOptions.config?.cors`, mecanismo REAL usado por
// `addCorsHeadersHandler` em `@fastify/cors/index.js` — nao publicado nos
// tipos oficiais do pacote, so no runtime). Task 5.1.1 (onda-012).
// ---------------------------------------------------------------------------
declare module 'fastify' {
  interface FastifyContextConfig {
    cors?: { methods?: readonly string[] };
  }
}

// ---------------------------------------------------------------------------
// §11.6 — formato estrito de `:questionId`, validado na borda ANTES de
// qualquer uso. Parametro de SQL sempre via placeholder `?` (nunca
// concatenacao), mas tambem compoe caminho de URL.
// ---------------------------------------------------------------------------
const QUESTION_ID_PATTERN = /^[A-Za-z0-9_-]{22,64}$/;

// ---------------------------------------------------------------------------
// §11.2 — defesa DNS-rebinding: Host aceito em loopback e, com opt-in
// EXPLICITO do operador (`CSTK_PANEL_ALLOWED_HOSTS`), nos hostnames listados.
//
// O opt-in existe para o deployment atras de proxy reverso, onde o `Host`
// repassado e o dominio publico e nunca seria loopback. Sem ele o default
// permanece "so loopback" — a mitigacao vale porque o hostname que o atacante
// faz resolver para 127.0.0.1 nao esta na lista do operador.
// ---------------------------------------------------------------------------
const LOOPBACK_HOSTNAMES: ReadonlySet<string> = new Set(['127.0.0.1', 'localhost', '[::1]', '::1']);

function extractHostname(hostHeader: string): string {
  if (hostHeader.startsWith('[')) {
    const end = hostHeader.indexOf(']');
    return end >= 0 ? hostHeader.slice(0, end + 1) : hostHeader;
  }
  const idx = hostHeader.lastIndexOf(':');
  return idx >= 0 ? hostHeader.slice(0, idx) : hostHeader;
}

// ---------------------------------------------------------------------------
// Linha de banco (snake_case) <-> DTO HTTP (camelCase) — mapper explicito,
// SEM ORM/auto-mapping, mesmo idioma de `routes/tasks.ts` (contrato §2).
// ---------------------------------------------------------------------------
interface InterventionRow {
  question_id: string;
  project_path: string;
  project: string;
  short_name: string | null;
  execution_kind: string;
  kind: string;
  question: string;
  options_json: string | null;
  default_value: string;
  resolution: string | null;
  applied_value: string | null;
  untrusted_text: string | null;
  expires_at: string;
  created_at: string;
  resolved_at: string | null;
}

/**
 * Estado DERIVADO na leitura — NUNCA coluna, NUNCA `UPDATE` disparado por
 * `GET` (contrato §5, data-model.md §"Estados derivados").
 */
function deriveState(
  row: Pick<InterventionRow, 'resolution' | 'expires_at'>,
  nowIso: string
): 'open' | 'answered' | 'declined' | 'expired' {
  if (row.resolution === 'answered' || row.resolution === 'declined') return row.resolution;
  if (nowIso >= row.expires_at) return 'expired';
  return 'open';
}

function parseOptions(optionsJson: string | null): string[] | null {
  if (optionsJson === null) return null;
  try {
    const parsed: unknown = JSON.parse(optionsJson);
    return Array.isArray(parsed) ? parsed.filter((v): v is string => typeof v === 'string') : null;
  } catch {
    return null;
  }
}

export async function bridgeRoutes(server: FastifyInstance): Promise<void> {
  const config = loadConfig();

  // Achado task 5.1.1 (onda-012, E2E real OBRIGATORIO): registrar
  // `@fastify/cors` de novo aqui SEMPRE que a arvore ancestral JA tem um
  // cors global (composicao real via `index.ts`) faz o servidor CRASHAR no
  // boot com `FST_ERR_DEC_ALREADY_PRESENT('corsPreflightEnabled')` —
  // `@fastify/cors` chama `fastify.decorateRequest('corsPreflightEnabled',
  // false)` INCONDICIONALMENTE (`@fastify/cors/index.js:46`) toda vez que o
  // plugin roda, e Fastify nao permite redeclarar um decorator ja presente
  // em QUALQUER ancestral da cadeia de encapsulamento (nao so no proprio
  // contexto). Nenhum teste anterior pegou isso porque
  // `test/routes/bridge.test.ts` registra `bridgeRoutes` ISOLADO (sem o cors
  // global de `index.ts`) — a PRIMEIRA vez que as duas coisas convivem na
  // MESMA arvore e quando o processo real sobe de verdade.
  //
  // Fix: registrar `@fastify/cors` aqui SO quando nao ha nenhum ja ativo no
  // ancestral (`hasRequestDecorator`, cobre o caso standalone dos testes —
  // a Ponte continua autossuficiente sem depender de `index.ts`). Quando ja
  // ha um cors global ativo (composicao real), usar o mecanismo OFICIAL de
  // override por rota do proprio `@fastify/cors` (`req.routeOptions.config
  // ?.cors`, ver `addCorsHeadersHandler` em `@fastify/cors/index.js`):
  // registrar rotas `OPTIONS` explicitas — MAIS ESPECIFICAS que a wildcard
  // `'*'` do plugin global — SO para os 2 endpoints POST desta Ponte, com
  // `config.cors.methods` ampliando o preflight so para eles. O CORS GLOBAL
  // (`index.ts`, `['GET','OPTIONS']`) continua intocado para o resto da API
  // — nunca alargado (§11.1/§11.2). `origin` sempre restrito a MESMA
  // allowlist do painel (controle de SEGURANCA, nao conveniencia de dev;
  // MUST NOT usar `origin: true`/`'*'`/reflexao do header `Origin`).
  const globalCorsAlreadyActive = server.hasRequestDecorator('corsPreflightEnabled');
  const BRIDGE_CORS_METHODS = ['GET', 'POST', 'OPTIONS'] as const;

  await server.register(async (scoped) => {
    if (!globalCorsAlreadyActive) {
      await scoped.register(cors, {
        origin: config.corsOrigin,
        methods: [...BRIDGE_CORS_METHODS],
      });
    } else {
      const preflightRouteOpts = { config: { cors: { methods: [...BRIDGE_CORS_METHODS] } } };
      // Handler nunca deveria executar de fato: o onRequest hook do cors
      // GLOBAL (herdado do ancestral) intercepta e responde o preflight
      // ANTES do preHandler/handler (mesmo comentario de
      // `@fastify/cors/index.js`: "preflight reply must occur in the
      // hook"). Existe so para dar a Fastify uma rota MAIS ESPECIFICA que a
      // wildcard `'*'` do plugin para casar `req.routeOptions.config.cors`.
      const preflightHandler = async (_request: FastifyRequest, reply: FastifyReply) =>
        reply.status(204).send();
      scoped.options('/bridge/interventions', preflightRouteOpts, preflightHandler);
      scoped.options('/bridge/interventions/:questionId/answer', preflightRouteOpts, preflightHandler);
    }

    // §11.2/§11.4 — defesa em profundidade contra CSRF e DNS rebinding,
    // aplicada a TODA rota deste escopo (leitura e escrita).
    scoped.addHook('preHandler', async (request: FastifyRequest, reply) => {
      if (request.method === 'POST') {
        const contentType = (request.headers['content-type'] ?? '').toLowerCase();
        if (!contentType.includes('application/json')) {
          return reply
            .status(415)
            .send(bridgeErrorEnvelope('Content-Type must be application/json (contrato §11.2)'));
        }
      }

      const hostHeader = request.headers.host ?? '';
      if (hostHeader !== '') {
        // DNS e case-insensitive: normalizar ANTES de comparar, senao
        // `Painel.Exemplo.Com` falharia contra uma allowlist em minusculas.
        // Comparacao por igualdade EXATA — nunca substring/wildcard (CWE-290).
        const hostname = extractHostname(hostHeader).toLowerCase();
        const allowed =
          LOOPBACK_HOSTNAMES.has(hostname) || config.bridgeAllowedHosts.has(hostname);
        if (!allowed) {
          return reply.status(400).send(bridgeErrorEnvelope('Host header rejeitado (contrato §11.2)'));
        }
      }

      return undefined;
    });

    // -----------------------------------------------------------------
    // POST /bridge/interventions — criar (chamador: servidor MCP). §4.
    // -----------------------------------------------------------------
    scoped.post('/bridge/interventions', async (request, reply) => {
      const parseResult = CreateInterventionRequestDTOSchema.safeParse(request.body);
      if (!parseResult.success) {
        const firstError = parseResult.error.errors[0];
        return reply.status(400).send(bridgeErrorEnvelope(firstError?.message ?? 'invalid body'));
      }
      const body = parseResult.data;

      let db: Database.Database | null = null;
      try {
        db = openBridgeDb();

        // §11.3 — question/options[] passam pelo MESMO pipeline de
        // untrusted_text: strip -> scrub (UMA vez) -> truncamento por
        // budget de bytes, na CRIACAO.
        const fieldsToSanitize = [body.question, ...(body.options ?? [])];
        const budgets = [QUESTION_MAX_BYTES, ...(body.options ?? []).map(() => OPTION_MAX_BYTES)];
        const sanitized = await sanitizeUntrustedFields(fieldsToSanitize, budgets);
        const question = sanitized[0] ?? '';
        const options = body.options ? sanitized.slice(1) : null;

        const questionId = randomUUID();
        const nowIso = new Date().toISOString();
        // §4 — timeoutMs e a janela EFETIVA ja resolvida pelo servidor MCP;
        // o painel MUST NOT re-derivar/re-clampar, so transportar.
        const expiresAt = new Date(Date.now() + body.timeoutMs).toISOString();

        db.prepare(
          `INSERT INTO interventions
            (question_id, project_path, project, short_name, execution_kind, kind,
             question, options_json, default_value, expires_at, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
        ).run(
          questionId,
          body.projectPath,
          body.project,
          body.shortName,
          body.executionKind,
          body.kind,
          question,
          options ? JSON.stringify(options) : null,
          body.defaultValue,
          expiresAt,
          nowIso
        );

        const data = { questionId, expiresAt, state: 'open' as const };
        return reply.status(201).send(wrapBridge(data, {}, resolveBridgeDbPath(), db));
      } catch {
        // bridge.db indisponivel (ausente/ilegivel/erro de escrita) — §3.1:
        // 200 + degraded=true, `data.questionId` OMITIDO (nada foi persistido).
        return reply.status(200).send(wrapBridgeDegraded('bridge_unavailable', resolveBridgeDbPath()));
      } finally {
        db?.close();
      }
    });

    // -----------------------------------------------------------------
    // GET /bridge/interventions/:questionId — polling (chamador: servidor MCP). §5.
    // -----------------------------------------------------------------
    scoped.get('/bridge/interventions/:questionId', async (request, reply) => {
      const { questionId } = request.params as { questionId: string };
      if (!QUESTION_ID_PATTERN.test(questionId)) {
        return reply.status(400).send(bridgeErrorEnvelope('questionId invalido (contrato §11.6)'));
      }

      let db: Database.Database | null = null;
      try {
        db = openBridgeDb();
        const row = db
          .prepare(
            `SELECT question_id, resolution, applied_value, untrusted_text, resolved_at, expires_at
               FROM interventions WHERE question_id = ?`
          )
          .get(questionId) as
          | Pick<InterventionRow, 'question_id' | 'resolution' | 'applied_value' | 'untrusted_text' | 'resolved_at' | 'expires_at'>
          | undefined;

        if (!row) {
          // O painel respondeu, so nao conhece o id — 404 (contrato §5: cliente MCP trata como `failed`).
          return reply.status(404).send(bridgeErrorEnvelope('questionId desconhecido'));
        }

        const nowIso = new Date().toISOString();
        const data = {
          questionId: row.question_id,
          state: deriveState(row, nowIso),
          appliedValue: row.applied_value,
          untrustedText: row.untrusted_text,
          resolvedAt: row.resolved_at,
        };
        return reply.status(200).send(wrapBridge(data, {}, resolveBridgeDbPath(), db));
      } catch {
        return reply.status(200).send(wrapBridgeDegraded('bridge_unavailable', resolveBridgeDbPath()));
      } finally {
        db?.close();
      }
    });

    // -----------------------------------------------------------------
    // GET /bridge/interventions — fila (chamador: painel/UI). §6.
    // -----------------------------------------------------------------
    const QueueQuerySchema = z.object({
      state: z.enum(['open', 'resolved', 'all']).optional(),
      project: z.string().optional(),
    });

    scoped.get('/bridge/interventions', async (request, reply) => {
      const queryResult = QueueQuerySchema.safeParse(request.query);
      const stateFilter = queryResult.success ? (queryResult.data.state ?? 'open') : 'open';
      const projectFilter = queryResult.success ? queryResult.data.project : undefined;
      const pagination = safeParsePagination(request.query as Record<string, string | undefined>);

      let db: Database.Database | null = null;
      try {
        db = openBridgeDb();
        const nowIso = new Date().toISOString();

        let sql = 'SELECT * FROM interventions WHERE 1 = 1';
        const params: unknown[] = [];
        if (stateFilter === 'open') {
          sql += ' AND resolution IS NULL AND expires_at > ?';
          params.push(nowIso);
        } else if (stateFilter === 'resolved') {
          sql += ' AND resolution IS NOT NULL';
        }
        // stateFilter === 'all' -> sem clausula extra de estado
        if (projectFilter) {
          sql += ' AND project = ?';
          params.push(projectFilter);
        }
        sql += ' ORDER BY created_at ASC LIMIT ? OFFSET ?';
        params.push(pagination.limit, pagination.offset);

        const rows = db.prepare(sql).all(...params) as InterventionRow[];

        const interventions = rows.map((r) => {
          const state = deriveState(r, nowIso);
          const reachable = existsSync(r.project_path);
          const waitingMs = Date.parse(nowIso) - Date.parse(r.created_at);
          return {
            questionId: r.question_id,
            project: r.project,
            shortName: r.short_name,
            executionKind: r.execution_kind,
            kind: r.kind,
            question: r.question,
            options: parseOptions(r.options_json),
            defaultValue: r.default_value,
            state,
            reachable,
            createdAt: r.created_at,
            expiresAt: r.expires_at,
            waitingMs,
            appliedValue: r.applied_value,
            untrustedText: r.untrusted_text,
            resolvedAt: r.resolved_at,
          };
        });

        const data = {
          interventions,
          pagination: { limit: pagination.limit, offset: pagination.offset },
        };
        return reply.status(200).send(wrapBridge(data, {}, resolveBridgeDbPath(), db));
      } catch {
        return reply.status(200).send(wrapBridgeDegraded('bridge_unavailable', resolveBridgeDbPath()));
      } finally {
        db?.close();
      }
    });

    // -----------------------------------------------------------------
    // POST /bridge/interventions/:questionId/answer — responder (chamador: painel/UI). §7.
    // -----------------------------------------------------------------
    scoped.post('/bridge/interventions/:questionId/answer', async (request, reply) => {
      const { questionId } = request.params as { questionId: string };
      if (!QUESTION_ID_PATTERN.test(questionId)) {
        return reply.status(400).send(bridgeErrorEnvelope('questionId invalido (contrato §11.6)'));
      }

      const parseResult = AnswerInterventionRequestDTOSchema.safeParse(request.body);
      if (!parseResult.success) {
        const firstError = parseResult.error.errors[0];
        return reply.status(400).send(bridgeErrorEnvelope(firstError?.message ?? 'invalid body'));
      }
      const body = parseResult.data;

      let db: Database.Database | null = null;
      try {
        db = openBridgeDb();

        const existing = db
          .prepare('SELECT kind, options_json FROM interventions WHERE question_id = ?')
          .get(questionId) as Pick<InterventionRow, 'kind' | 'options_json'> | undefined;

        if (!existing) {
          return reply.status(404).send(bridgeErrorEnvelope('questionId desconhecido'));
        }

        // FR-005 — validacao de SERVIDOR, nunca so de UI.
        if (body.text != null && existing.kind !== 'text') {
          return reply.status(400).send(bridgeErrorEnvelope("text so e permitido quando kind='text'"));
        }

        let untrustedText: string | null = null;
        if (body.resolution === 'answered') {
          if (existing.kind === 'choice') {
            const options = parseOptions(existing.options_json) ?? [];
            if (!body.value || !options.includes(body.value)) {
              return reply.status(400).send(bridgeErrorEnvelope('value fora de options (contrato §7)'));
            }
          } else if (existing.kind === 'confirm') {
            if (body.value !== 'yes' && body.value !== 'no') {
              return reply.status(400).send(bridgeErrorEnvelope("value deve ser 'yes' ou 'no' (contrato §7)"));
            }
          } else if (existing.kind === 'text') {
            if (!body.value) {
              return reply.status(400).send(bridgeErrorEnvelope('value (token de desfecho) obrigatorio'));
            }
            if (body.text != null) {
              untrustedText = await sanitizeUntrustedInput(body.text, TEXT_MAX_BYTES);
            }
          }
        }

        const nowIso = new Date().toISOString();
        const appliedValue = body.resolution === 'answered' ? (body.value ?? null) : null;

        // FR-016/SC-006 — idempotencia por INVARIANTE DE BANCO, nunca
        // SELECT-then-UPDATE (janela de corrida). Cobre os dois Edge Cases
        // de uma vez: duas respostas concorrentes E resposta apos expirar.
        const result = db
          .prepare(
            `UPDATE interventions
                SET resolution = ?, applied_value = ?, untrusted_text = ?, resolved_at = ?
              WHERE question_id = ? AND resolution IS NULL AND expires_at > ?`
          )
          .run(body.resolution, appliedValue, untrustedText, nowIso, questionId, nowIso);

        if (result.changes === 0) {
          return reply.status(409).send(bridgeErrorEnvelope('intervencao ja resolvida ou expirada (contrato §7)'));
        }

        const finalRow = db
          .prepare(
            `SELECT question_id, resolution, applied_value, untrusted_text, resolved_at, expires_at
               FROM interventions WHERE question_id = ?`
          )
          .get(questionId) as Pick<
          InterventionRow,
          'question_id' | 'resolution' | 'applied_value' | 'untrusted_text' | 'resolved_at' | 'expires_at'
        >;

        const data = {
          questionId: finalRow.question_id,
          state: deriveState(finalRow, nowIso),
          appliedValue: finalRow.applied_value,
          untrustedText: finalRow.untrusted_text,
          resolvedAt: finalRow.resolved_at,
        };
        return reply.status(200).send(wrapBridge(data, {}, resolveBridgeDbPath(), db));
      } catch {
        return reply.status(200).send(wrapBridgeDegraded('bridge_unavailable', resolveBridgeDbPath()));
      } finally {
        db?.close();
      }
    });
  });
}
