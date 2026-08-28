/**
 * Utilitario para construcao de queries FTS5 seguras.
 * Ref: research.md §Decision 6; spec.md FR-020; contracts/search-fts.md
 * Task 3.5.3
 *
 * Principio I (Read-Only Absoluto): FTS5 permite construcoes especiais como
 * `') OR 1=1 --'` que podem produzir erros de sintaxe ou queries inesperadas.
 * A sanitizacao aqui garante que apenas busca de tokens ocorra.
 *
 * Estrategia: tokenizar por whitespace, envolver cada token em aspas duplas
 * (duplicando aspas internas conforme especificacao FTS5), juntar com espaco.
 * Resultado: `termo1 "ter mo2" "term\"s"` — cada token e buscado como frase.
 *
 * Limite de tokens: 10 (SC-005 — previne queries FTS5 excessivamente complexas)
 */

const FTS_MAX_TOKENS = 10;

/**
 * Sanitiza input do usuario para query FTS5 segura.
 *
 * - Tokeniza por whitespace
 * - Remove tokens vazios
 * - Limita a FTS_MAX_TOKENS tokens
 * - Duplica aspas duplas internas (escape FTS5)
 * - Envolve cada token em aspas duplas
 *
 * @param input  String de busca do usuario (potencialmente hostil)
 * @returns      String de query FTS5 segura, ou '' se nenhum token valido
 *
 * @example
 * sanitizeFts("npm install")       → '"npm" "install"'
 * sanitizeFts("') OR 1=1 --")      → '"\')" "OR" "1=1" "--"'
 * sanitizeFts('"aspas"')           → '"\"aspas\""'
 */
export function sanitizeFts(input: string): string {
  if (!input || typeof input !== 'string') return '';

  const tokens = input
    .trim()
    .split(/\s+/)
    .filter((t) => t.length > 0)
    .slice(0, FTS_MAX_TOKENS);

  if (tokens.length === 0) return '';

  // Cada token: escapar aspas duplas internas duplicando-as, depois envolver em ""
  return tokens
    .map((token) => `"${token.replace(/"/g, '""')}"`)
    .join(' ');
}

/**
 * Valida se o input e adequado para FTS5 (apos sanitizacao).
 * Retorna false se a query sanitizada seria vazia.
 */
export function isValidFtsInput(input: string): boolean {
  return sanitizeFts(input).length > 0;
}
