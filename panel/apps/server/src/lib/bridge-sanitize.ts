/**
 * Pipeline de sanitizacao de entrada UNTRUSTED da Ponte (`routes/bridge.ts`).
 * Ref: docs/specs/human-bridge/contracts/panel-bridge-api.md §7, §11.3
 * Tasks: 3.1.2, 3.1.5
 *
 * Ordem OBRIGATORIA, sempre a mesma, para `question`/`options[]` (na criacao)
 * e `text` (na resposta):
 *
 *   1. strip de caracteres de controle
 *   2. `secrets-filter.sh scrub` (UMA vez) — reusa a cadeia ja existente do
 *      painel (`lib/secret-scrub.ts`, feature session-tail); NAO spawna um
 *      segundo subprocesso de scrub
 *   3. truncamento por budget de BYTES (UTF-8, respeitando code points —
 *      nunca corta um caractere multi-byte ao meio)
 *
 * §11.3 (achado do gate `owasp-security`): a assimetria anterior aplicava
 * scrub so a `untrusted_text`; `question`/`options[]` MUST passar pelo MESMO
 * pipeline (agente pode vazar segredo no texto da pergunta).
 */
import { scrubTextBatch } from './secret-scrub.js';

/** Padrao de caracteres de controle (mesmo conjunto de `mcp/state-server/src/runtime/sanitize.ts`),
 *  construido via `RegExp` com codigos hex escritos como TEXTO (nunca `\\u`
 *  literal no fonte) para nao virar um NUL/controle real dentro deste arquivo. */
// Disable deliberado: e o pattern que remove caracteres de controle da
// entrada UNTRUSTED (mesmo racional de mcp/state-server/src/runtime/sanitize.ts).
// eslint-disable-next-line no-control-regex
const CONTROL_CHARS_PATTERN = new RegExp('[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]', 'g');

/** Remove caracteres de controle. */
export function stripControlChars(text: string): string {
  return text.replace(CONTROL_CHARS_PATTERN, ' ');
}

/**
 * Trunca respeitando um teto de BYTES (UTF-8), iterando por CODE POINT —
 * nunca corta um caractere multi-byte ao meio.
 */
export function truncateUtf8ByteBudget(text: string, maxBytes: number): string {
  const codePoints = Array.from(text);
  let bytes = 0;
  let truncated = '';
  for (const ch of codePoints) {
    const chBytes = Buffer.byteLength(ch, 'utf8');
    if (bytes + chBytes > maxBytes) break;
    truncated += ch;
    bytes += chBytes;
  }
  return truncated;
}

/**
 * Budgets de bytes — decisao de design desta feature (nao um valor extraido
 * de contrato externo): `TEXT_MAX_BYTES` e o UNICO numero citado
 * literalmente pelo contrato (§7, "truncamento a 2048 bytes"). Os demais
 * (`question`/`options[]`) seguem a mesma ordem de grandeza — o contrato so
 * exige "o MESMO pipeline... com truncamento por budget de bytes" (§11.3),
 * sem fixar o numero.
 */
export const QUESTION_MAX_BYTES = 4096;
export const OPTION_MAX_BYTES = 512;
export const TEXT_MAX_BYTES = 2048;

/**
 * Aplica o pipeline completo (strip -> scrub -> truncate) a VARIOS campos em
 * uma UNICA invocacao de subprocesso de scrub (via `scrubTextBatch`) —
 * mesmo idioma de "um spawn por requisicao", nunca um por campo. Cada campo
 * pode ter um budget de bytes proprio (`maxBytesList`, mesma ordem/contagem
 * de `rawTexts`); o ultimo valor de `maxBytesList` e reusado se a lista for
 * mais curta que `rawTexts` (defensivo — nao deveria ocorrer no uso real).
 */
export async function sanitizeUntrustedFields(
  rawTexts: readonly string[],
  maxBytesList: readonly number[]
): Promise<string[]> {
  if (rawTexts.length === 0) return [];
  const stripped = rawTexts.map(stripControlChars);
  const { texts: scrubbed } = await scrubTextBatch(stripped);
  return scrubbed.map((t, i) => {
    const budget = maxBytesList[i] ?? maxBytesList[maxBytesList.length - 1] ?? t.length;
    return truncateUtf8ByteBudget(t, budget);
  });
}

/** Conveniencia para UM UNICO campo (ex.: `text` na resposta). */
export async function sanitizeUntrustedInput(raw: string, maxBytes: number): Promise<string> {
  const [result] = await sanitizeUntrustedFields([raw], [maxBytes]);
  return result ?? '';
}
