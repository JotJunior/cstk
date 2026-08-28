/**
 * Geracao de ETag para respostas da API.
 * Ref: research.md §Decision 7; spec.md FR-014
 * Task 3.2.7
 *
 * Formato: W/"<mtime_epoch>-<max_ingested_at_epoch>"
 * W/ indica ETag "fraco" (weak) — comparacao semantica, nao byte-a-byte.
 *
 * ETag baseado em:
 * - mtime do arquivo: proxy de quando a base foi modificada
 * - max(ingested_at): garante que novas ingestoes invalidas o cache
 *
 * Ambos como epoch ms para comparacao numerica rapida.
 */
import type { Freshness } from '@cstk-panel/shared-types';

/**
 * Gera ETag fraco a partir do Freshness do snapshot.
 * Retorna null se freshness esta vazio (modo degradado sem DB).
 */
export function generateETag(freshness: Freshness): string | null {
  const { mtime, maxIngestedAt } = freshness;
  if (!mtime && !maxIngestedAt) return null;

  // Converter para epoch ms para compacidade
  const mtimeEpoch = mtime ? new Date(mtime).getTime() : 0;
  const maxEpoch = maxIngestedAt ? new Date(maxIngestedAt).getTime() : 0;

  return `W/"${mtimeEpoch}-${maxEpoch}"`;
}

/**
 * Verifica se o ETag do request coincide com o ETag atual.
 * Suporta lista de ETags (If-None-Match pode ter multiplos valores).
 */
export function etagMatches(
  requestETag: string | undefined,
  currentETag: string | null
): boolean {
  if (!requestETag || !currentETag) return false;
  // If-None-Match pode ser "ETag1, ETag2, *"
  const tags = requestETag.split(',').map((t) => t.trim());
  return tags.includes(currentETag) || tags.includes('*');
}
