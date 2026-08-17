// tools/collect_optins.ts — tool `collect_optins`: 8a tool do servidor
// `cstk-state`. Oferece UM formulario estruturado (`elicitation/create`) com
// os opt-ins de inicio de execucao aplicaveis ao orquestrador corrente
// (`atomic_commit`, `roadmap_mode`, `delivery_tier`) e persiste as respostas.
//
// Ref: docs/specs/mcp-elicitation-optins/contracts/mcp-tool-collect-optins.md
//      docs/specs/mcp-elicitation-optins/data-model.md (Entity RespostaDeOptIn)
//      docs/specs/mcp-elicitation-optins/tasks.md FASE 3 (3.1-3.5) + FASE 4.1
//
// NOTA DE ESCOPO (dec-074): tasks.md organiza os subtitulos "FASE 3" (mecanica
// da tool) e "FASE 4.1" (persistencia — 3 helpers de camada 1 +
// `.optin_responses[]` de camada 2) como blocos de leitura separados. Na
// pratica, `data-model.md` §Primitiva de escrita e explicito que E ESTA tool
// quem chama os 3 helpers de camada 1 e o `state-rw.sh set` de camada 2 — sem
// essas escritas o tool nao cumpre a Invariante I-2 (FR-012: nenhuma onda pode
// abrir com campo aplicavel sem registro). Este arquivo implementa FASE 3
// (3.1-3.5) e FASE 4.1 (4.1.1-4.1.5) juntas, como uma unidade funcional. FASE
// 4.2 (round-trip empirico sob backend SQLite) permanece tarefa separada —
// validacao, nao codigo.
//
// Delega, quando `outcome === "accepted"` (Invariante C-3 — nenhuma escrita
// para os demais desfechos, o default seguro ja foi gravado pela etapa 1 do
// init):
//   commit-mode.sh set-enabled --state-dir <SD> --value <true|false>
//   roadmap-mode.sh set-enabled --state-dir <SD> --value <true|false>
//   delivery-tier.sh set --state-dir <SD> --value <token> [--allow-downgrade]
//   delivery-tier.sh get --state-dir <SD>  (tier vigente p/ mensagem + ordinal)
//   state-rw.sh get/set --field '.optin_responses' (camada 2, append-only)

import { join } from "node:path";
import { z } from "zod";
import { McpError, ErrorCode, type ElicitRequestFormParams, type ElicitResult } from "@modelcontextprotocol/sdk/types.js";
import {
  runHelper,
  resolveScriptsDir,
  HelperExecutionError,
  formatToolError,
} from "../runtime/exec.js";
import { sanitizeForLlmContext } from "../runtime/sanitize.js";
import {
  matchesResolvedSession,
  type ResolvedSession,
} from "../session/resolve.js";

const MAX_REASON_BYTES = 2048; // 2 KiB (SEC-M1)

function sanitizeHelperReason(stderr: string): string {
  return sanitizeForLlmContext(stderr, MAX_REASON_BYTES);
}

// ---------------------------------------------------------------------------
// Schema de entrada — so `session_id` (task 3.1.1). Nenhum outro parametro:
// o escopo de campos e derivado server-side de `executionKind` (FR-003).
// ---------------------------------------------------------------------------

export const collectOptinsInputShape = {
  session_id: z.string().min(1, "session_id obrigatorio"),
} as const;

const collectOptinsInputSchema = z.object(collectOptinsInputShape);

export type CollectOptinsInput = z.infer<typeof collectOptinsInputSchema>;

// ---------------------------------------------------------------------------
// Tipos do envelope de resposta (contracts/mcp-tool-collect-optins.md)
// ---------------------------------------------------------------------------

export type CollectOptinsOutcome = "accepted" | "rejected";
export type CollectOptinsStage = "precondition" | "delegation" | null;

export type FieldName = "atomic_commit" | "roadmap_mode" | "delivery_tier";

export type FieldOutcomeValue =
  | "accepted"
  | "declined"
  | "absent"
  | "timeout"
  | "unavailable"
  | "failed";

export type Mechanism = "structured" | "unavailable" | "failed";

export interface FieldOutcome {
  readonly field: FieldName;
  readonly outcome: FieldOutcomeValue;
  readonly applied_value: string;
}

export interface CollectOptinsResult {
  readonly mechanism: Mechanism;
  readonly fields: readonly FieldOutcome[];
  readonly reused: readonly string[];
}

export interface CollectOptinsResponse {
  readonly outcome: CollectOptinsOutcome;
  readonly reason: string | null;
  readonly stage: CollectOptinsStage;
  readonly result: CollectOptinsResult | null;
}

// ---------------------------------------------------------------------------
// Deps — inclui o "server" com acesso a elicitInput/getClientCapabilities
// [VERIFICADO: server/index.d.ts:158, server/index.d.ts:121]. Tipo estrutural
// minimo (nao o `Server` completo do SDK) para manter os testes de unidade
// sem precisar instanciar um McpServer real.
// ---------------------------------------------------------------------------

export interface ElicitationServer {
  getClientCapabilities(): { readonly elicitation?: unknown } | undefined;
  elicitInput(
    params: ElicitRequestFormParams,
    options?: { readonly timeout?: number },
  ): Promise<ElicitResult>;
}

export interface CollectOptinsDeps {
  readonly session: ResolvedSession;
  readonly env?: NodeJS.ProcessEnv;
  readonly elicitationServer: ElicitationServer;
  /** Override do path de `commit-mode.sh`. */
  readonly commitModeHelperPath?: string;
  /** Override do path de `roadmap-mode.sh`. */
  readonly roadmapModeHelperPath?: string;
  /** Override do path de `delivery-tier.sh`. */
  readonly deliveryTierHelperPath?: string;
  /** Override do path de `state-rw.sh` (leitura/escrita de `.optin_responses`). */
  readonly stateRwHelperPath?: string;
}

// ---------------------------------------------------------------------------
// Escopo de campos por executionKind (contracts §Escopo de campos)
// ---------------------------------------------------------------------------

const FIELDS_BY_EXECUTION_KIND: Readonly<Record<string, readonly FieldName[]>> = {
  "agente-00c": ["atomic_commit", "roadmap_mode", "delivery_tier"],
  "feature-00c": ["atomic_commit", "roadmap_mode"],
};

function applicableFieldsFor(executionKind: string): readonly FieldName[] {
  return FIELDS_BY_EXECUTION_KIND[executionKind] ?? [];
}

/** Valor seguro que JA foi gravado pela etapa 1 do init (C-3: nunca reescrito aqui para outcome != accepted). */
const SAFE_DEFAULTS: Readonly<Record<FieldName, string>> = {
  atomic_commit: "false",
  roadmap_mode: "false",
  delivery_tier: "cloud-public",
};

/**
 * Allowlist explicita de tokens aceitos no mapper wire->helper (task 3.4.2,
 * SEC-H1 estendido): nenhum valor fora deste conjunto chega a `execFile`.
 * Um `content[field]` fora da allowlist e tratado como `failed` — nunca
 * repassado ao helper POSIX.
 */
const WIRE_ALLOWLIST: Readonly<Record<FieldName, readonly string[]>> = {
  atomic_commit: ["nao", "sim"],
  roadmap_mode: ["nao", "sim"],
  delivery_tier: ["local", "internal-network", "cloud-internal", "cloud-public"],
};

/** Ordinal do enum `delivery_tier` [VERIFICADO: `delivery-tier.sh:96-107`]. */
const TIER_ORDER: readonly string[] = [
  "local",
  "internal-network",
  "cloud-internal",
  "cloud-public",
];

function tierOrdinal(token: string): number {
  return TIER_ORDER.indexOf(token);
}

// ---------------------------------------------------------------------------
// Teto de tempo (task 3.4.1, dec-058): clamp por fallback-ao-default —
// mesmo padrao de `parseMaxToolCalls` (index.ts): entrada ausente/invalida/
// fora da faixa MUST cair no default, nunca desabilitar o teto nem propagar
// um valor fora de [MIN, MAX]. Faixa 5s-600s escolhida para acomodar o
// default de 300000ms como valor INTERNO a faixa (nao no teto — plan.md
// §Riscos observou que 5s-300s colocaria o default exatamente no limite,
// impossibilitando override por env acima do default).
// ---------------------------------------------------------------------------

const DEFAULT_ELICIT_TIMEOUT_MS = 300000;
const MIN_ELICIT_TIMEOUT_MS = 5000;
const MAX_ELICIT_TIMEOUT_MS = 600000;

export function parseElicitTimeoutMs(raw: string | undefined): number {
  if (raw === undefined || raw === "") return DEFAULT_ELICIT_TIMEOUT_MS;
  if (!/^[0-9]+$/.test(raw)) return DEFAULT_ELICIT_TIMEOUT_MS;
  const parsed = Number(raw);
  if (!Number.isSafeInteger(parsed)) return DEFAULT_ELICIT_TIMEOUT_MS;
  if (parsed < MIN_ELICIT_TIMEOUT_MS || parsed > MAX_ELICIT_TIMEOUT_MS) {
    return DEFAULT_ELICIT_TIMEOUT_MS;
  }
  return parsed;
}

// ---------------------------------------------------------------------------
// Formulario (task 3.1.3, 3.2, ajuste dec-071)
// ---------------------------------------------------------------------------

interface StringEnumProperty {
  readonly type: "string";
  readonly title: string;
  readonly description: string;
  readonly enum: readonly string[];
  readonly default?: string;
}

/**
 * Texto/nomes derivados dos blocos de prosa existentes (FR-002) —
 * `plugins/cstk/commands/agente-00c.md` linhas ~297-439 (prompts opt-in de
 * commit atomico / roadmap / tier), nao redigidos do zero.
 */
function buildProperties(fields: readonly FieldName[]): Record<string, StringEnumProperty> {
  const properties: Record<string, StringEnumProperty> = {};
  if (fields.includes("atomic_commit")) {
    properties.atomic_commit = {
      type: "string",
      title: "Modo atomic-commit",
      description:
        "Cria um commit git a cada etapa concluida (specify, plan, checklist, " +
        "create-tasks) e um commit agrupado ao final de cada onda de " +
        "execute-task. Ao final da pipeline, faz push+PR automaticamente se " +
        "houver branch nao-default.",
      enum: [...WIRE_ALLOWLIST.atomic_commit],
      default: "nao",
    };
  }
  if (fields.includes("roadmap_mode")) {
    properties.roadmap_mode = {
      type: "string",
      title: "Modo roadmap",
      description:
        "Em vez da pipeline completa, a execucao para apos briefing + " +
        "constitution + a redacao de um roadmap de features priorizadas " +
        "(docs/roadmap.md) — util para so planejar o portfolio.",
      enum: [...WIRE_ALLOWLIST.roadmap_mode],
      default: "nao",
    };
  }
  if (fields.includes("delivery_tier")) {
    properties.delivery_tier = {
      type: "string",
      title: "Finalidade de entrega",
      description:
        "Calibra a profundidade de arquitetura/seguranca: 1) uso local " +
        "(sem rede exposta); 2) rede interna compartilhada; 3) nuvem de uso " +
        "interno; 4) nuvem de uso publico.",
      enum: [...WIRE_ALLOWLIST.delivery_tier],
      // SEM `default` (dec-071/requisito b): nasce visivelmente obrigatorio
      // (`* not set`) — o default seguro cloud-public e aplicado pelo
      // SERVIDOR (SAFE_DEFAULTS acima) em cancel/decline/timeout, nunca
      // pre-marcado na tela.
    };
  }
  return properties;
}

/**
 * `message` (task 3.2.1 + requisito (a) derivado do Scenario 0, dec-071):
 * campo obrigatorio do schema, MEDIDO como renderizado integralmente
 * (contracts/mcp-tool-collect-optins.md §Campo `message`). Quando
 * `delivery_tier` entra no formulario, nomeia o tier vigente + eixo do enum
 * (H1, dec-047) e avisa que os campos de enum estao colapsados (seta para
 * expandir — item 4 do contrato, dec-071).
 */
function buildMessage(fields: readonly FieldName[], currentTier: string | null): string {
  const expandWarning =
    "Os campos de opcoes (enum) aparecem colapsados — use a seta " +
    "(→ to expand) para ver todas as opcoes antes de responder.";

  if (!fields.includes("delivery_tier")) {
    return (
      "Formulario de opt-ins de inicio de execucao: modo atomic-commit e " +
      `modo roadmap (ambos opcionais, default 'nao'). ${expandWarning}`
    );
  }

  const tier = currentTier ?? "cloud-public";
  return (
    `Formulario de opt-ins de inicio de execucao. Tier de entrega vigente: ` +
    `'${tier}' (eixo local < internal-network < cloud-internal < ` +
    `cloud-public, do menor para o maior rigor de gates). ATENCAO: escolher ` +
    `um tier ABAIXO do vigente reduz a profundidade dos gates que auditam ` +
    `esta propria execucao. ${expandWarning}`
  );
}

// ---------------------------------------------------------------------------
// Camada 2 — `.optin_responses[]` (data-model.md §Primitiva de escrita)
// ---------------------------------------------------------------------------

interface StoredOptinResponse {
  readonly field: string;
  readonly channel: string;
  readonly outcome: FieldOutcomeValue;
  readonly applied_value: string;
  readonly recorded_at: string;
  readonly reason: string | null;
}

function isStoredOptinResponse(value: unknown): value is StoredOptinResponse {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as { field?: unknown }).field === "string" &&
    typeof (value as { recorded_at?: unknown }).recorded_at === "string"
  );
}

async function readOptinResponses(
  stateRwHelperPath: string,
  stateDir: string,
): Promise<readonly StoredOptinResponse[]> {
  const { stdout } = await runHelper(stateRwHelperPath, [
    "get",
    "--state-dir",
    stateDir,
    "--field",
    ".optin_responses // []",
  ]);
  const parsed: unknown = JSON.parse(stdout);
  if (!Array.isArray(parsed)) return [];
  return parsed.filter(isStoredOptinResponse);
}

function mostRecentByField(
  records: readonly StoredOptinResponse[],
  fields: readonly FieldName[],
): ReadonlyMap<FieldName, StoredOptinResponse> {
  const map = new Map<FieldName, StoredOptinResponse>();
  for (const rec of records) {
    if (!fields.includes(rec.field as FieldName)) continue;
    const existing = map.get(rec.field as FieldName);
    if (!existing || rec.recorded_at >= existing.recorded_at) {
      map.set(rec.field as FieldName, rec);
    }
  }
  return map;
}

async function appendOptinResponses(
  stateRwHelperPath: string,
  stateDir: string,
  entries: readonly { field: FieldName; outcome: FieldOutcomeValue; applied_value: string; reason: string | null }[],
): Promise<void> {
  const existing = await readOptinResponses(stateRwHelperPath, stateDir);
  const now = new Date().toISOString();
  const appended: StoredOptinResponse[] = [
    ...existing,
    ...entries.map((e) => ({
      field: e.field,
      channel: "structured" as const,
      outcome: e.outcome,
      applied_value: e.applied_value,
      recorded_at: now,
      reason: e.reason,
    })),
  ];
  await runHelper(stateRwHelperPath, [
    "set",
    "--state-dir",
    stateDir,
    "--field",
    ".optin_responses",
    "--value",
    JSON.stringify(appended),
  ]);
}

// ---------------------------------------------------------------------------
// Camada 1 — write dos 3 helpers existentes (SOMENTE outcome === "accepted",
// Invariante C-3). Retorna o outcome/applied_value FINAIS apos a tentativa
// de escrita (escrita falha => outcome vira "failed", applied_value reflete
// o que permanece em vigor).
// ---------------------------------------------------------------------------

async function writeBooleanField(
  helperPath: string,
  stateDir: string,
  wireValue: string,
): Promise<{ outcome: FieldOutcomeValue; applied_value: string; reason: string | null }> {
  const mapped = wireValue === "sim" ? "true" : "false";
  try {
    await runHelper(helperPath, ["set-enabled", "--state-dir", stateDir, "--value", mapped]);
    return { outcome: "accepted", applied_value: mapped, reason: null };
  } catch (err) {
    const message =
      err instanceof HelperExecutionError ? (err.diagnostic?.message ?? err.stderr) : String(err);
    console.error(`collect_optins: escrita de camada 1 falhou (1 linha, FR-009): ${sanitizeHelperReason(message)}`);
    return { outcome: "failed", applied_value: mapped, reason: sanitizeHelperReason(message) };
  }
}

async function writeDeliveryTier(
  deliveryTierHelperPath: string,
  stateDir: string,
  wireValue: string,
): Promise<{ outcome: FieldOutcomeValue; applied_value: string; reason: string | null }> {
  let currentTier: string;
  try {
    const { stdout } = await runHelper(deliveryTierHelperPath, ["get", "--state-dir", stateDir]);
    currentTier = stdout.trim();
  } catch {
    currentTier = SAFE_DEFAULTS.delivery_tier;
  }

  const args = ["set", "--state-dir", stateDir, "--value", wireValue];
  // Invariante contratual C-2 (dec-047): --allow-downgrade SOMENTE quando o
  // novo ordinal e ESTRITAMENTE menor que o vigente, lido IMEDIATAMENTE
  // antes da escrita — nunca incondicional.
  if (tierOrdinal(wireValue) < tierOrdinal(currentTier)) {
    args.push("--allow-downgrade");
  }

  try {
    await runHelper(deliveryTierHelperPath, args);
    return { outcome: "accepted", applied_value: wireValue, reason: null };
  } catch (err) {
    const message =
      err instanceof HelperExecutionError ? (err.diagnostic?.message ?? err.stderr) : String(err);
    console.error(`collect_optins: escrita de camada 1 (delivery_tier) falhou (1 linha, FR-009): ${sanitizeHelperReason(message)}`);
    return { outcome: "failed", applied_value: currentTier, reason: sanitizeHelperReason(message) };
  }
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

export async function handleCollectOptins(
  input: CollectOptinsInput,
  deps: CollectOptinsDeps,
): Promise<CollectOptinsResponse> {
  const { session, env = process.env } = deps;

  if (!matchesResolvedSession(session, input.session_id)) {
    return {
      outcome: "rejected",
      reason: formatToolError({
        code: "SESSION_MISMATCH",
        message: "session_id nao corresponde ao token de capacidade desta sessao",
      }),
      stage: "precondition",
      result: null,
    };
  }

  const scriptsDir = resolveScriptsDir(env);
  const commitModeHelperPath = deps.commitModeHelperPath ?? join(scriptsDir, "commit-mode.sh");
  const roadmapModeHelperPath = deps.roadmapModeHelperPath ?? join(scriptsDir, "roadmap-mode.sh");
  const deliveryTierHelperPath = deps.deliveryTierHelperPath ?? join(scriptsDir, "delivery-tier.sh");
  const stateRwHelperPath = deps.stateRwHelperPath ?? join(scriptsDir, "state-rw.sh");

  const applicableFields = applicableFieldsFor(session.executionKind);
  if (applicableFields.length === 0) {
    return {
      outcome: "accepted",
      reason: null,
      stage: null,
      result: { mechanism: "unavailable", fields: [], reused: [] },
    };
  }

  // ---- Cap M6 (task 3.3): 1 chamada de coleta por execucao ----
  let existingResponses: readonly StoredOptinResponse[];
  try {
    existingResponses = await readOptinResponses(stateRwHelperPath, session.stateDir);
  } catch (err) {
    const message = err instanceof HelperExecutionError ? (err.diagnostic?.message ?? err.stderr) : String(err);
    return {
      outcome: "rejected",
      reason: sanitizeHelperReason(formatToolError({ code: "HELPER_FAILED", message: `leitura de .optin_responses: ${message}` })),
      stage: "delegation",
      result: null,
    };
  }

  const mostRecent = mostRecentByField(existingResponses, applicableFields);
  if (mostRecent.size === applicableFields.length) {
    // task 3.3.2: segunda tentativa de coleta fora do padrao normal de
    // retomada — sinalizar anomalia, nao apenas silenciar.
    console.error(
      `collect_optins: ANOMALIA (cap M6) — nova tentativa de coleta para ` +
        `execucao '${session.shortName}' com todos os campos aplicaveis ja ` +
        `registrados; elicitInput NAO sera re-disparado (reuso).`,
    );
    const fields: FieldOutcome[] = applicableFields.map((field) => {
      const rec = mostRecent.get(field);
      return { field, outcome: rec?.outcome ?? "failed", applied_value: rec?.applied_value ?? SAFE_DEFAULTS[field] };
    });
    return {
      outcome: "accepted",
      reason: null,
      stage: null,
      result: { mechanism: "structured", fields, reused: [...applicableFields] },
    };
  }

  // ---- Capability check (task 3.1.4: unavailable = detectado ANTES da chamada) ----
  const capabilities = deps.elicitationServer.getClientCapabilities();
  if (!capabilities?.elicitation) {
    const fields: FieldOutcome[] = applicableFields.map((field) => ({
      field,
      outcome: "unavailable",
      applied_value: SAFE_DEFAULTS[field],
    }));
    try {
      await appendOptinResponses(
        stateRwHelperPath,
        session.stateDir,
        fields.map((f) => ({ ...f, reason: null })),
      );
    } catch (err) {
      const message = err instanceof HelperExecutionError ? (err.diagnostic?.message ?? err.stderr) : String(err);
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(formatToolError({ code: "HELPER_FAILED", message: `persistencia .optin_responses: ${message}` })),
        stage: "delegation",
        result: null,
      };
    }
    return {
      outcome: "accepted",
      reason: null,
      stage: null,
      result: { mechanism: "unavailable", fields, reused: [] },
    };
  }

  // ---- Montagem do formulario ----
  let currentTierForMessage: string | null = null;
  if (applicableFields.includes("delivery_tier")) {
    try {
      const { stdout } = await runHelper(deliveryTierHelperPath, ["get", "--state-dir", session.stateDir]);
      currentTierForMessage = stdout.trim();
    } catch {
      currentTierForMessage = null; // buildMessage cai no default seguro para exibicao
    }
  }
  const message = buildMessage(applicableFields, currentTierForMessage);
  const properties = buildProperties(applicableFields);
  const timeoutMs = parseElicitTimeoutMs(env.MCP_ELICIT_TIMEOUT_MS);

  let elicitResult: ElicitResult;
  let mechanismOnError: Mechanism | null = null;
  let fieldsOnError: FieldOutcome[] | null = null;
  try {
    elicitResult = await deps.elicitationServer.elicitInput(
      {
        message,
        requestedSchema: { type: "object", properties },
      } as ElicitRequestFormParams,
      { timeout: timeoutMs },
    );
  } catch (err) {
    if (err instanceof McpError && err.code === ErrorCode.RequestTimeout) {
      mechanismOnError = "structured";
      fieldsOnError = applicableFields.map((field) => ({
        field,
        outcome: "timeout",
        applied_value: SAFE_DEFAULTS[field],
      }));
    } else {
      const message2 = err instanceof Error ? err.message : String(err);
      console.error(`collect_optins: 1 linha (FR-009) — elicitInput falhou: ${sanitizeHelperReason(message2)}`);
      mechanismOnError = "failed";
      fieldsOnError = applicableFields.map((field) => ({
        field,
        outcome: "failed",
        applied_value: SAFE_DEFAULTS[field],
      }));
    }

    try {
      await appendOptinResponses(
        stateRwHelperPath,
        session.stateDir,
        fieldsOnError.map((f) => ({ ...f, reason: mechanismOnError === "failed" ? "elicitInput lancou excecao" : null })),
      );
    } catch (persistErr) {
      const pMessage =
        persistErr instanceof HelperExecutionError ? (persistErr.diagnostic?.message ?? persistErr.stderr) : String(persistErr);
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(formatToolError({ code: "HELPER_FAILED", message: `persistencia .optin_responses: ${pMessage}` })),
        stage: "delegation",
        result: null,
      };
    }

    return {
      outcome: "accepted",
      reason: null,
      stage: null,
      result: { mechanism: mechanismOnError, fields: fieldsOnError, reused: [] },
    };
  }

  // ---- Mapeamento resultado -> outcome (task 3.1.4) ----
  const fields: FieldOutcome[] = [];
  const persistedReasons: (string | null)[] = [];

  for (const field of applicableFields) {
    if (elicitResult.action === "decline") {
      fields.push({ field, outcome: "declined", applied_value: SAFE_DEFAULTS[field] });
      persistedReasons.push(null);
      continue;
    }
    if (elicitResult.action === "cancel") {
      fields.push({ field, outcome: "absent", applied_value: SAFE_DEFAULTS[field] });
      persistedReasons.push(null);
      continue;
    }
    // action === "accept"
    const raw = elicitResult.content?.[field];
    if (raw === undefined) {
      fields.push({ field, outcome: "absent", applied_value: SAFE_DEFAULTS[field] });
      persistedReasons.push(null);
      continue;
    }
    const wireValue = String(raw);
    if (!WIRE_ALLOWLIST[field].includes(wireValue)) {
      // task 3.4.2: token fora da allowlist NUNCA chega a execFile.
      console.error(
        `collect_optins: 1 linha (FR-009) — content['${field}'] fora da allowlist, tratado como falha (nunca repassado ao helper)`,
      );
      fields.push({ field, outcome: "failed", applied_value: SAFE_DEFAULTS[field] });
      persistedReasons.push(`token fora da allowlist para '${field}'`);
      continue;
    }

    // Invariante C-3: so escreve camada 1 para outcome === "accepted".
    const written =
      field === "delivery_tier"
        ? await writeDeliveryTier(deliveryTierHelperPath, session.stateDir, wireValue)
        : await writeBooleanField(
            field === "atomic_commit" ? commitModeHelperPath : roadmapModeHelperPath,
            session.stateDir,
            wireValue,
          );
    fields.push({ field, outcome: written.outcome, applied_value: written.applied_value });
    persistedReasons.push(written.reason);
  }

  try {
    await appendOptinResponses(
      stateRwHelperPath,
      session.stateDir,
      fields.map((f, idx) => ({ ...f, reason: persistedReasons[idx] ?? null })),
    );
  } catch (err) {
    const message = err instanceof HelperExecutionError ? (err.diagnostic?.message ?? err.stderr) : String(err);
    return {
      outcome: "rejected",
      reason: sanitizeHelperReason(formatToolError({ code: "HELPER_FAILED", message: `persistencia .optin_responses: ${message}` })),
      stage: "delegation",
      result: null,
    };
  }

  return {
    outcome: "accepted",
    reason: null,
    stage: null,
    result: { mechanism: "structured", fields, reused: [] },
  };
}
