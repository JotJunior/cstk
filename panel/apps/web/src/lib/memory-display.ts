/**
 * Derivacao defensiva do rotulo de descricao de uma memoria (tela Memorias).
 *
 * O produtor (cstk recall) define `memories.description` como a 1a linha
 * NAO-vazia do `.md`. Como os `.md` de auto-memoria comecam com frontmatter
 * YAML (`---`), essa heuristica captura o delimitador `---` na maioria dos
 * casos (observado: 86% da base real). O painel e read-only e NAO reescreve o
 * indice; aqui derivamos um rotulo melhor APENAS para exibicao, na ordem:
 *   1. `description` do produtor, se for prosa util (nao ruido de frontmatter);
 *   2. campo `description:` do frontmatter YAML do corpo;
 *   3. 1a linha de prosa do corpo (apos o frontmatter, sem headings);
 *   4. slug humanizado.
 *
 * Conteudo UNTRUSTED: o retorno e string crua, renderizada via textContent.
 */

/** Linhas que sao puro delimitador YAML — nunca servem de descricao. */
const FRONTMATTER_NOISE = new Set(['---', '...']);

/** Chaves de frontmatter comuns — uma linha `chave: valor` nao e descricao. */
function looksLikeFrontmatterKey(line: string): boolean {
  return /^(name|description|metadata|type|created|updated|tags|aliases)\s*:/i.test(line);
}

function humanizeSlug(slug: string): string {
  return slug.replace(/[_-]+/g, ' ').trim() || slug;
}

function stripQuotes(s: string): string {
  return s.replace(/^["']/, '').replace(/["']$/, '').trim();
}

/** Indice (exclusivo) do fim do bloco de frontmatter, ou 0 se nao houver. */
function frontmatterEnd(lines: string[]): number {
  if (lines[0]?.trim() !== '---') return 0;
  for (let i = 1; i < lines.length; i++) {
    if (lines[i]?.trim() === '---') return i + 1;
  }
  return 0; // frontmatter sem fechamento — trata o corpo inteiro como prosa
}

/** Extrai o valor de `description:` do frontmatter YAML, se presente. */
function frontmatterDescription(lines: string[]): string | null {
  const end = frontmatterEnd(lines);
  if (end === 0) return null;
  for (let i = 1; i < end - 1; i++) {
    const m = /^description\s*:\s*(.+)$/i.exec(lines[i] ?? '');
    if (m && m[1] && m[1].trim() !== '') return stripQuotes(m[1]);
  }
  return null;
}

/** 1a linha de prosa apos o frontmatter (ignora vazias, ruido e headings). */
function firstProseLine(lines: string[]): string | null {
  for (let i = frontmatterEnd(lines); i < lines.length; i++) {
    const raw = (lines[i] ?? '').trim();
    if (raw === '' || FRONTMATTER_NOISE.has(raw) || looksLikeFrontmatterKey(raw)) continue;
    const clean = raw.replace(/^#+\s*/, '').trim(); // remove marcacao de heading
    if (clean !== '') return clean;
  }
  return null;
}

export interface MemoryLike {
  slug: string;
  description: string | null;
  body: string | null;
}

/** Rotulo de descricao para exibicao — sempre nao-vazio. */
export function memoryDisplayDescription(m: MemoryLike): string {
  const desc = (m.description ?? '').trim();
  const noisy = desc === '' || FRONTMATTER_NOISE.has(desc) || looksLikeFrontmatterKey(desc);
  if (!noisy) return desc;

  const lines = (m.body ?? '').split('\n');
  return frontmatterDescription(lines) ?? firstProseLine(lines) ?? humanizeSlug(m.slug);
}
