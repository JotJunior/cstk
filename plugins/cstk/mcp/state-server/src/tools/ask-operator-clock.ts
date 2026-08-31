// tools/ask-operator-clock.ts — politica de relogios da superficie
// `ask_operator` (human-bridge). Modulo de config DEDICADO (task 1.3, "ou
// modulo de config dedicado") porque `tools/ask_operator.ts` ainda nao
// existe nesta onda — nasce so na FASE 2 (task 2.2). Este arquivo e o ponto
// de import que `ask_operator.ts` e `index.ts` consumirao la.
//
// Ref: docs/specs/human-bridge/contracts/mcp-tool-ask-operator.md §4
//      (R-CLOCK-1 a R-CLOCK-7); docs/specs/human-bridge/research.md Decision 7
// Tasks: 1.3.1 - 1.3.4

/**
 * Piso PROPRIO da superficie `ask_operator` (R-CLOCK-7) — janela minima
 * plausivel para um humano notar a fila, ler a pergunta e responder.
 * `timeout_ms` requisitado abaixo deste valor e tratado como fora da faixa
 * (R-CLOCK-4): cai no DEFAULT, nunca e clampado para a borda.
 *
 * MUST NOT compartilhar `const`/identidade com `CLOCK_SAFETY_MARGIN_MS`,
 * mesmo sendo numericamente igual — motivos independentes (research.md
 * Decision 7 / block-005 / dec-031). "Duas constantes, dois porques, duas
 * vidas": esta mede janela minima de resposta humana; a outra mede overshoot
 * do watchdog de ociosidade do cliente. Um ajuste legitimo numa NUNCA MUST
 * afetar a outra.
 */
export const ASK_MIN_TIMEOUT_MS = 60000;

/**
 * Folga MINIMA obrigatoria (R-CLOCK-2) entre o teto do servidor
 * (`MCP_ASK_TIMEOUT_MS`) e o teto total do cliente (`client_timeout_ms`):
 * overshoot medido de ~30s do watchdog de ociosidade do cliente + 30s de
 * margem. Ver nota de nao-unificacao em `ASK_MIN_TIMEOUT_MS` acima.
 */
export const CLOCK_SAFETY_MARGIN_MS = 60000;

/**
 * Valor assumido para `client_timeout_ms` quando `CSTK_CLIENT_TOOL_TIMEOUT_MS`
 * esta ausente/invalida (R-CLOCK-5) — mesmo valor proposto para o `timeout`
 * do `.mcp.json` (contrato §4).
 */
export const DEFAULT_CLIENT_TIMEOUT_MS = 300000;

/** Faixa derivada de MCP_ASK_TIMEOUT_MS para um dado client_timeout_ms. */
export interface AskTimeoutRange {
  readonly min: number;
  readonly max: number;
  readonly default: number;
}

/**
 * Deriva a faixa valida de `MCP_ASK_TIMEOUT_MS` a partir de
 * `clientTimeoutMs` (R-CLOCK-4): `[ASK_MIN_TIMEOUT_MS, clientTimeoutMs -
 * CLOCK_SAFETY_MARGIN_MS]`, com `default` = topo da faixa (coerente por
 * construcao — nunca literal).
 */
export function deriveAskTimeoutRange(clientTimeoutMs: number): AskTimeoutRange {
  const max = clientTimeoutMs - CLOCK_SAFETY_MARGIN_MS;
  return { min: ASK_MIN_TIMEOUT_MS, max, default: max };
}

/** Resultado da validacao de boot (R-CLOCK-5). */
export interface BootValidationResult {
  readonly ok: boolean;
  readonly reason?: string;
}

/**
 * Valida se `clientTimeoutMs` produz uma faixa LEGAL (R-CLOCK-5): combinacao
 * EXPLICITAMENTE ilegal (`max < min`, ou seja `clientTimeoutMs` baixo demais
 * para caber a folga da R-CLOCK-2 + o piso da R-CLOCK-7) reprova. A
 * degradacao de env var AUSENTE (que MUST NOT reprovar) e tratada por
 * `resolveClientTimeoutMs`/`resolveAndValidateBootTimeout`, nunca aqui.
 */
export function validateClientTimeoutMs(clientTimeoutMs: number): BootValidationResult {
  const { max, min } = deriveAskTimeoutRange(clientTimeoutMs);
  if (max < min) {
    return {
      ok: false,
      reason:
        `CSTK_CLIENT_TOOL_TIMEOUT_MS=${clientTimeoutMs} produz uma faixa ilegal para ` +
        `ask_operator: max=${max} < min=${min} (R-CLOCK-2/R-CLOCK-4). Aumente ` +
        `CSTK_CLIENT_TOOL_TIMEOUT_MS para pelo menos ${min + CLOCK_SAFETY_MARGIN_MS}.`,
    };
  }
  return { ok: true };
}

/** Resultado da resolucao de `client_timeout_ms` a partir do ambiente. */
export interface ClientTimeoutResolution {
  readonly clientTimeoutMs: number;
  readonly usedDefault: boolean;
}

/**
 * Resolve `client_timeout_ms` a partir de `CSTK_CLIENT_TOOL_TIMEOUT_MS`
 * (R-CLOCK-5): ausente, vazio, nao-numerico ou nao-inteiro-seguro/`<= 0`
 * degrada para `DEFAULT_CLIENT_TIMEOUT_MS` — NUNCA recusa por variavel
 * opcional ausente/invalida. `usedDefault` sinaliza ao caller que o aviso de
 * 1 linha em stderr (R-CLOCK-5) deve ser emitido.
 */
export function resolveClientTimeoutMs(raw: string | undefined): ClientTimeoutResolution {
  if (raw === undefined || raw.trim() === "") {
    return { clientTimeoutMs: DEFAULT_CLIENT_TIMEOUT_MS, usedDefault: true };
  }
  if (!/^[0-9]+$/.test(raw.trim())) {
    return { clientTimeoutMs: DEFAULT_CLIENT_TIMEOUT_MS, usedDefault: true };
  }
  const parsed = Number(raw.trim());
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    return { clientTimeoutMs: DEFAULT_CLIENT_TIMEOUT_MS, usedDefault: true };
  }
  return { clientTimeoutMs: parsed, usedDefault: false };
}

/**
 * parseAskTimeoutMs — espelha EXATAMENTE a politica VERIFICADA de
 * `parseElicitTimeoutMs` (`collect_optins.ts:196-205`): `requested`
 * ausente/vazio/nao-numerico/nao-inteiro-seguro/fora de `[min, max]` cai no
 * DEFAULT (topo da faixa derivada), NUNCA clampado para a borda.
 *
 * `requested` aceita `string | number | undefined` (zod/JSON podem entregar
 * number; a normalizacao interna usa a MESMA rotina de validacao de digitos
 * de `parseElicitTimeoutMs`, sem introduzir uma segunda forma de parsing
 * numerico nesta superficie).
 */
export function parseAskTimeoutMs(
  clientTimeoutMs: number,
  requested: string | number | undefined,
): number {
  const range = deriveAskTimeoutRange(clientTimeoutMs);
  if (requested === undefined || requested === "") return range.default;
  const raw = typeof requested === "number" ? String(requested) : requested;
  if (!/^[0-9]+$/.test(raw)) return range.default;
  const parsed = Number(raw);
  if (!Number.isSafeInteger(parsed)) return range.default;
  if (parsed < range.min || parsed > range.max) return range.default;
  return parsed;
}

/** Lancada por `resolveAndValidateBootTimeout` quando a combinacao e ilegal. */
export class BootTimeoutError extends Error {}

/** Resultado do boot bem-sucedido. */
export interface BootClientTimeout {
  readonly clientTimeoutMs: number;
}

/**
 * Resolve + valida `client_timeout_ms` de boot como UMA unidade (R-CLOCK-5):
 *
 * - env ausente/invalida -> assume `DEFAULT_CLIENT_TIMEOUT_MS` e emite
 *   EXATAMENTE 1 linha de aviso via `warn` (default: stderr) — NUNCA recusa.
 * - combinacao presente porem EXPLICITAMENTE ilegal -> lanca
 *   `BootTimeoutError`. O caller (index.ts, FASE 2, task 2.2/2.5) decide
 *   como abortar a subida do processo a partir dessa excecao.
 *
 * `warn` e injetavel para manter este modulo puro/testavel sem capturar
 * `process.stderr` real nos testes.
 */
export function resolveAndValidateBootTimeout(
  env: NodeJS.ProcessEnv = process.env,
  warn: (message: string) => void = (message: string) => {
    process.stderr.write(`${message}\n`);
  },
): BootClientTimeout {
  const { clientTimeoutMs, usedDefault } = resolveClientTimeoutMs(
    env["CSTK_CLIENT_TOOL_TIMEOUT_MS"],
  );
  if (usedDefault) {
    const derivedMax = DEFAULT_CLIENT_TIMEOUT_MS - CLOCK_SAFETY_MARGIN_MS;
    warn(
      `ask_operator: CSTK_CLIENT_TOOL_TIMEOUT_MS ausente/invalida — assumindo ` +
        `${DEFAULT_CLIENT_TIMEOUT_MS}ms (teto MCP_ASK_TIMEOUT_MS derivado: ${derivedMax}ms). ` +
        `Provisione CSTK_CLIENT_TOOL_TIMEOUT_MS (cli/lib/mcp.sh) para eliminar este aviso.`,
    );
  }
  const validation = validateClientTimeoutMs(clientTimeoutMs);
  if (!validation.ok) {
    throw new BootTimeoutError(validation.reason);
  }
  return { clientTimeoutMs };
}
