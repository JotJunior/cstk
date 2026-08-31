// runtime/sanitize.ts — primitivas de saneamento de texto livre vindo de
// helpers POSIX (SEC-M1: stderr/argumentos de tool sao DADO, podem ter
// sido influenciados por conteudo lido pelo LLM — LLM05 / injecao
// indireta). Extraido de `tools/record_skill.ts` (task 2.2.5, onde vivia
// como `sanitizeHelperReason` privada) para reuso por `audit/log.ts`
// (task 2.3) e por futuras tools de F3 — uma unica implementacao evita a
// mesma logica divergir entre tools ao longo do tempo.
//
// Ref: docs/specs/state-mcp-server/contracts/mcp-tools.md §SEC-M1
//      docs/specs/state-mcp-server/data-model.md §Regra de sanitizacao
//      (Tool Invocation Audit Record — "truncamento MUST ocorrer em code
//      points, nao bytes")

/** Remove caracteres de controle (exceto os ja tratados pelo serializador JSON, ex.: `\n`). */
export function stripControlChars(text: string): string {
  // eslint-disable-next-line no-control-regex
  return text.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/gu, " ");
}

/**
 * Trunca respeitando um teto de BYTES (UTF-8), iterando por CODE POINT
 * para nunca cortar um caractere multi-byte ao meio (cortar no meio
 * produziria um caractere de substituicao invalido / quebraria o JSON
 * downstream). Usado onde o limite e expresso em unidade de
 * armazenamento/transporte (ex.: 2 KiB de contexto de LLM, SEC-M1).
 */
export function truncateUtf8ByteBudget(text: string, maxBytes: number): string {
  const codePoints = Array.from(text);
  let bytes = 0;
  let truncated = "";
  for (const ch of codePoints) {
    const chBytes = Buffer.byteLength(ch, "utf8");
    if (bytes + chBytes > maxBytes) break;
    truncated += ch;
    bytes += chBytes;
  }
  return truncated;
}

/**
 * Trunca por CONTAGEM de code points (nao bytes) — usado onde o contrato
 * expressa o limite como numero de caracteres (ex.: precedente
 * `cut -c1-500` de `pretooluse-bash-guard.sh`, herdado por
 * `arguments_digest` em data-model.md).
 */
export function truncateCodePoints(text: string, maxCodePoints: number): string {
  const codePoints = Array.from(text);
  if (codePoints.length <= maxCodePoints) return text;
  return codePoints.slice(0, maxCodePoints).join("");
}

const DEFAULT_EMPTY_FALLBACK = "helper falhou sem mensagem de erro utilizavel";

/**
 * SEC-M1: strip -> trim -> truncate(bytes), com fallback textual quando o
 * resultado fica vazio (stderr vazio ou so caracteres de controle). Usado
 * pelo `reason` devolvido ao CHAMADOR da tool (contexto do LLM) — nao
 * aplica `secrets-filter.sh scrub` (isso e responsabilidade separada de
 * `audit/log.ts` para o que e PERSISTIDO EM DISCO, FR-006).
 */
export function sanitizeForLlmContext(
  text: string,
  maxBytes: number,
  emptyFallback: string = DEFAULT_EMPTY_FALLBACK,
): string {
  const cleaned = truncateUtf8ByteBudget(stripControlChars(text).trim(), maxBytes);
  return cleaned || emptyFallback;
}
