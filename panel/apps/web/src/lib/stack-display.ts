/**
 * Derivacao defensiva dos chips de stack sugerida (ExecutionDetail / FeatureDetail).
 *
 * O produtor (agente-00c) grava `executions.stack_sugerida` como JSON — observado
 * em duas formas na base real:
 *   - array de strings:  ["react 19", "vite", "nodejs"]
 *   - objeto chave/valor: { "language": "TypeScript 5.4", "runtime": "Node >=20", ... }
 * Fixtures legadas ainda usam string simples separada por virgula (ex.: "node+ts").
 *
 * O painel e read-only e NAO normaliza a base; aqui derivamos a lista de chips
 * APENAS para exibicao, tolerando as tres formas:
 *   1. JSON array  -> cada item vira um chip (objeto/array aninhado e serializado);
 *   2. JSON objeto -> cada par vira o chip "chave: valor";
 *   3. JSON primitivo / texto nao-JSON -> split por virgula (compat. legado).
 *
 * Conteudo UNTRUSTED: o retorno e string crua, renderizada via textContent.
 */

/** Serializa um valor de item de array para um token de chip legivel. */
function tokenizeValue(v: unknown): string {
  if (v == null) return '';
  if (typeof v === 'string') return v.trim();
  if (typeof v === 'number' || typeof v === 'boolean') return String(v);
  return JSON.stringify(v); // objeto/array aninhado — serializa em vez de "[object Object]"
}

/** Quebra string nao-JSON (legado) em tokens por virgula. */
function splitCsv(raw: string): string[] {
  return raw.split(',').map(s => s.trim()).filter(Boolean);
}

/**
 * Lista de chips para exibir a stack sugerida — sempre array (vazio se nao ha dado).
 */
export function stackDisplayItems(raw: string | null | undefined): string[] {
  const trimmed = (raw ?? '').trim();
  if (trimmed === '') return [];

  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    return splitCsv(trimmed); // nao e JSON — trata como CSV legado
  }

  if (Array.isArray(parsed)) {
    return parsed.map(tokenizeValue).filter(Boolean);
  }

  if (parsed !== null && typeof parsed === 'object') {
    return Object.entries(parsed as Record<string, unknown>)
      .map(([k, v]) => {
        const val = tokenizeValue(v);
        return val ? `${k}: ${val}` : k;
      })
      .filter(Boolean);
  }

  // primitivo JSON (string/number/boolean) — cai no caminho CSV legado
  return splitCsv(tokenizeValue(parsed));
}
