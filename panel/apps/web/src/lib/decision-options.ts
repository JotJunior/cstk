/**
 * Derivacao das opcoes consideradas de uma decisao (DecisionsPanel).
 *
 * A ingestao (agente-00c → recall schema v6) grava `decisions.opcoes` como JSON
 * array cru de `.decisoes[].opcoes_consideradas`, ex.: `["haiku","sonnet"]`.
 * Bases v<6 nao tem a coluna → o DTO traz `null` e nao ha o que exibir.
 *
 * O painel e read-only e NAO normaliza a base; aqui derivamos a lista de chips
 * APENAS para exibicao, reaproveitando o parser defensivo de `stackDisplayItems`
 * (tolera JSON array/objeto e o caso CSV legado). Conteudo estruturado, mas
 * renderizado via textContent (nunca innerHTML).
 */
import { stackDisplayItems } from './stack-display.js';

/** Lista de opcoes para exibir — sempre array (vazio se nao ha dado). */
export function decisionOptions(raw: string | null | undefined): string[] {
  return stackDisplayItems(raw);
}

/** Normaliza um token para comparacao tolerante (case/espaco-insensitive). */
function normalize(s: string): string {
  return s.trim().toLowerCase();
}

/** Trecho de `escolha` apos o ultimo `:` (cobre namespaces como `model:sonnet`). */
function tailAfterColon(s: string): string {
  return s.slice(s.lastIndexOf(':') + 1).trim();
}

/** True se `prefix` e prefixo de `s` terminando numa fronteira (nao corta token). */
function isPrefixAtBoundary(s: string, prefix: string): boolean {
  if (prefix === '' || !s.startsWith(prefix)) return false;
  if (s.length === prefix.length) return true;
  // proximo char nao pode ser alfanumerico (senao e o meio de uma palavra/token)
  return !/[a-z0-9]/i.test(s.charAt(prefix.length));
}

/**
 * Indice da opcao que corresponde a `escolha` — best-effort, no maximo uma.
 *
 * A `escolha` raramente e identica a opcao: as vezes vem com prefixo de
 * namespace (`model:sonnet`), as vezes ELABORA a opcao escolhida
 * (`"MVP enxuto...: fetch + parse..."` para a opcao `"MVP enxuto..."`). Pontuamos
 * cada opcao e destacamos so a de maior score, evitando marcar a alternativa
 * errada numa tela de auditoria. Retorna -1 quando nada casa com confianca.
 */
export function chosenOptionIndex(options: string[], escolha: string | null): number {
  if (!escolha) return -1;
  const esc = normalize(escolha);
  if (esc === '') return -1;
  const tail = tailAfterColon(esc);

  let bestIdx = -1;
  let bestScore = 0;
  options.forEach((opt, i) => {
    const o = normalize(opt);
    if (o === '') return;
    let score = 0;
    if (o === esc || o === tail) {
      score = 1_000_000;                       // match exato — confianca maxima
    } else if (isPrefixAtBoundary(esc, o) || isPrefixAtBoundary(o, esc)) {
      // escolha elabora a opcao (ou vice-versa) — score = tamanho do prefixo
      // comum, para preferir o casamento mais especifico entre opcoes irmas.
      score = Math.min(o.length, esc.length);
    }
    if (score > bestScore) {
      bestScore = score;
      bestIdx = i;
    }
  });
  return bestIdx;
}
